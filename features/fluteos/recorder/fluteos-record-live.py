#!/usr/bin/env python3
# Live transcription of a meeting while it is still being recorded.
#
# Reads raw linear16 mono PCM from a unix socket ffmpeg connects to — the
# second output of the same encoder that writes the segments — and streams it
# to Deepgram's WebSocket endpoint,
# appending finalised turns to live.jsonl and live.md in the recording
# directory as they arrive.
#
# The recording on disk is the thing that must not break, and this process sits
# downstream of it, so every decision here is made in its favour:
#
#   * the socket is drained UNCONDITIONALLY, connected to Deepgram or not. The
#     write side is ffmpeg, and a tap that stops reading is a tap that slows
#     the encoder down. Audio that cannot be sent onwards is dropped instead.
#   * a dropped connection is not fatal. The socket is reopened and the gap is
#     recorded as a gap, because a transcript that silently skips four minutes
#     is worse than one that says it skipped them.
#   * nothing here writes to the segments, ever.
#
# Speaker numbers come from Deepgram's diarisation over ONE continuous
# connection, so unlike the segment-at-a-time batch pass they mean the same
# person throughout — until a reconnect, which starts the numbering over and is
# marked as such in the transcript.

import json
import os
import queue
import signal
import socket
import sys
import threading
import time
import urllib.parse

import websocket

SAMPLE_RATE = int(os.environ.get("SAMPLE_RATE", "16000"))
BYTES_PER_SECOND = SAMPLE_RATE * 2

# 100 ms per frame: small enough that interim results feel immediate, large
# enough that a two-hour meeting is not four hundred thousand sends.
CHUNK = BYTES_PER_SECOND // 10

# Roughly 30 s of audio. The queue exists to ride out a reconnect, not to
# buffer a meeting: past this, the oldest frames are dropped, because sending
# stale audio to a speech recogniser is worse than admitting the hole.
QUEUE_FRAMES = 300

RECONNECT_WAIT = 2.0

# Deepgram closes a stream that has gone quiet for about ten seconds, so the
# silence between sentences is answered well inside that.
KEEPALIVE_SECONDS = 5.0

# How long a silent socket is given before it is treated as dead. Comfortably
# longer than the keepalive, so a quiet meeting never trips it.
RECV_TIMEOUT = 30.0


def log(message):
    print(message, file=sys.stderr, flush=True)


def hhmmss(seconds):
    seconds = int(seconds or 0)
    return f"{seconds // 3600:02d}:{(seconds % 3600) // 60:02d}:{seconds % 60:02d}"


class Transcript:
    """The two files the window and the reader-afterwards both read.

    live.jsonl is the record — one JSON object per line, appended and never
    rewritten, so a crash costs nothing that had already arrived. live.md is
    the same thing rendered for a human, and is rebuilt from what is held in
    memory whenever it changes: consecutive turns by one speaker are joined,
    which cannot be done by appending alone.
    """

    def __init__(self, directory):
        self.jsonl = os.path.join(directory, "live.jsonl")
        self.markdown = os.path.join(directory, "live.md")
        self.turns = []
        self.lock = threading.Lock()

    def _append_jsonl(self, obj):
        with open(self.jsonl, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(obj, ensure_ascii=False) + "\n")

    def _render(self):
        lines = []
        for turn in self.turns:
            if turn.get("gap"):
                lines.append(
                    f"**[{hhmmss(turn['start'])}] — connection lost, "
                    f"speaker numbering restarts —**\n"
                )
                continue
            lines.append(
                f"**[{hhmmss(turn['start'])}] Speaker {turn['speaker']}**\n\n"
                f"{turn['text']}\n"
            )
        tmp = self.markdown + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines))
        os.replace(tmp, self.markdown)

    def add(self, start, end, speaker, text):
        text = text.strip()
        if not text:
            return
        with self.lock:
            self._append_jsonl(
                {"start": start, "end": end, "speaker": speaker, "text": text}
            )
            last = self.turns[-1] if self.turns else None
            if last and not last.get("gap") and last["speaker"] == speaker:
                last["text"] += " " + text
                last["end"] = end
            else:
                self.turns.append(
                    {"start": start, "end": end, "speaker": speaker, "text": text}
                )
            self._render()

    def add_gap(self, at):
        with self.lock:
            self._append_jsonl({"start": at, "gap": True})
            self.turns.append({"start": at, "gap": True})
            self._render()


class Interim:
    """The line that is still being spoken.

    Its own file, replaced in place rather than appended: it is a preview, it
    is wrong about a third of the time, and nothing should ever read it back as
    part of the transcript.
    """

    def __init__(self, directory):
        self.path = os.path.join(directory, ".live-interim")

    def set(self, text):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp, self.path)

    def clear(self):
        self.set("")


class Audio:
    """A unix socket ffmpeg connects to, drained into a bounded queue by a
    thread that never waits on the network.

    A SOCKET, not a pipe, and the reason is what happens when this process is
    not there: connecting to a socket nobody is listening on fails immediately,
    while opening a FIFO for writing BLOCKS until a reader appears. Measured on
    the real thing — with a pipe, ffmpeg could not exit at the end of a
    recording once its reader had died, and systemd eventually killed it,
    truncating the final segment. With a socket it retries, is refused, and
    finishes the meeting cleanly.

    ffmpeg reconnects after a failure, so the accept loop runs for as long as
    the meeting does rather than ending with the first connection.

    `sent_seconds` is how much audio has gone past this point, which is what
    turns Deepgram's per-connection timestamps into meeting time.
    """

    def __init__(self, path):
        self.path = path
        self.frames = queue.Queue(maxsize=QUEUE_FRAMES)
        self.read_bytes = 0
        self.dropped_frames = 0
        self.stopped = threading.Event()

    @property
    def sent_seconds(self):
        return self.read_bytes / BYTES_PER_SECOND

    def listen(self):
        try:
            os.unlink(self.path)
        except OSError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(self.path)
        os.chmod(self.path, 0o600)
        server.listen(1)
        server.settimeout(0.5)
        return server

    def run(self, server):
        while not self.stopped.is_set():
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            connection.settimeout(0.5)
            # A THREAD per connection, rather than draining this one before
            # accepting the next. ffmpeg's fifo muxer opens a fresh connection
            # every time it recovers and does not always close the one it left
            # behind — so a client that drains them one at a time sits on a
            # dead connection while the live audio piles up unaccepted in the
            # backlog. Measured mid-meeting: 2% of the stream arriving, the
            # rest thrown away by the kernel buffer filling up.
            threading.Thread(
                target=self.drain, args=(connection,), daemon=True
            ).start()
        try:
            server.close()
            os.unlink(self.path)
        except OSError:
            pass

    def drain(self, connection):
        with connection:
            while not self.stopped.is_set():
                try:
                    chunk = connection.recv(CHUNK)
                except socket.timeout:
                    continue
                except OSError:
                    return
                if not chunk:
                    return
                self.read_bytes += len(chunk)
                try:
                    self.frames.put_nowait(chunk)
                except queue.Full:
                    try:
                        self.frames.get_nowait()
                        self.dropped_frames += 1
                    except queue.Empty:
                        pass
                    try:
                        self.frames.put_nowait(chunk)
                    except queue.Full:
                        pass


def socket_url():
    endpoint = os.environ.get("ENDPOINT", "wss://api.deepgram.com/v1/listen")
    params = {
        "model": os.environ.get("MODEL", "nova-3"),
        "encoding": "linear16",
        "sample_rate": str(SAMPLE_RATE),
        "channels": "1",
        "interim_results": "true",
        "punctuate": "true",
        "smart_format": "true",
        "diarize": "true",
        "utterance_end_ms": "1000",
    }
    language = os.environ.get("LANGUAGE", "").strip()
    if language:
        params["language"] = language
    return f"{endpoint}?{urllib.parse.urlencode(params)}"


def api_key():
    directory = os.environ.get("CREDENTIALS_DIRECTORY", "")
    if directory:
        path = os.path.join(directory, "deepgram")
        try:
            with open(path, encoding="utf-8") as handle:
                return handle.read().strip()
        except OSError:
            pass
    return ""


def speaker_of(alternative):
    """Deepgram puts the speaker on each word, not on the alternative.

    A finalised result can span a change of speaker; taking the first word's
    label keeps a turn attributed to whoever began it, which is what reads
    correctly when the next result opens the other speaker's turn.
    """
    for word in alternative.get("words") or []:
        if "speaker" in word:
            return int(word["speaker"])
    return 0


def pump(session_url, key, audio, transcript, interim, offset):
    """One connection, for as long as it lasts. Returns when it is over."""
    connection = websocket.create_connection(
        session_url,
        header=[f"Authorization: Token {key}"],
        timeout=10,
        enable_multithread=True,
    )
    # The handshake gets ten seconds; reading does NOT inherit that. Deepgram
    # says nothing at all while nobody is speaking, so a ten-second read
    # timeout meant every quiet moment in a meeting looked like a dead socket:
    # the connection was torn down and rebuilt, the speaker numbering restarted,
    # and the audio that arrived mid-reconnect went nowhere. Sending KeepAlive
    # keeps DEEPGRAM from hanging up; this is the other half, and without it the
    # client hangs up on itself.
    connection.settimeout(RECV_TIMEOUT)
    log("connected")

    stop = threading.Event()

    def send():
        # Deepgram closes a stream that goes quiet, and a meeting goes quiet
        # constantly — somebody is thinking, or the call is on mute. Silence is
        # not the absence of a meeting, so it is answered with KeepAlive rather
        # than allowed to drop the socket and restart the speaker numbering.
        idle_since = time.monotonic()
        while not stop.is_set():
            try:
                frame = audio.frames.get(timeout=0.5)
            except queue.Empty:
                if audio.stopped.is_set():
                    break
                if time.monotonic() - idle_since > KEEPALIVE_SECONDS:
                    idle_since = time.monotonic()
                    try:
                        connection.send(json.dumps({"type": "KeepAlive"}))
                    except Exception as error:
                        log(f"keepalive failed: {error}")
                        break
                continue
            idle_since = time.monotonic()
            try:
                connection.send_binary(frame)
            except Exception as error:  # the receive side reports the reason
                log(f"send failed: {error}")
                break
        try:
            # Deepgram flushes what it is holding and closes, so the last words
            # of a meeting arrive instead of dying with the socket.
            connection.send(json.dumps({"type": "CloseStream"}))
        except Exception:
            pass

    pending = None

    sender = threading.Thread(target=send, daemon=True)
    sender.start()

    try:
        while True:
            try:
                raw = connection.recv()
            except websocket.WebSocketTimeoutException:
                # Nothing said for half a minute. The keepalives are still
                # going out; if they had stopped the sender would be gone and
                # there would be nothing left to wait for.
                if not sender.is_alive():
                    break
                continue
            if not raw:
                break
            if isinstance(raw, bytes):
                continue
            message = json.loads(raw)
            kind = message.get("type")

            if kind == "Results":
                channel = message.get("channel") or {}
                alternatives = channel.get("alternatives") or [{}]
                alternative = alternatives[0]
                text = (alternative.get("transcript") or "").strip()
                if not text:
                    continue
                start = offset + float(message.get("start") or 0.0)
                if message.get("is_final"):
                    end = start + float(message.get("duration") or 0.0)
                    transcript.add(start, end, speaker_of(alternative), text)
                    pending = None
                    interim.clear()
                else:
                    # Held, not just displayed. A preview that never gets its
                    # final — the socket drops, the meeting ends, Deepgram
                    # decides the utterance is over — used to be wiped off the
                    # screen, so words appeared and then went missing from the
                    # transcript entirely. Whatever is being held is written
                    # down before this connection ends.
                    pending = (start, text)
                    interim.set(text)

            elif kind == "UtteranceEnd":
                # NOT cleared. The next interim replaces it, the next final
                # supersedes it, and the end of the connection commits it.
                pass

            elif kind == "Metadata":
                log("stream closed by Deepgram")
                break

            elif kind == "Error":
                log(f"Deepgram error: {raw[:300]}")
                break
    finally:
        stop.set()
        # Commit whatever was still only a preview, so the words on screen a
        # moment ago are in the transcript rather than gone. It is the last
        # thing anybody said on this connection; leaving it out loses the end
        # of every meeting.
        if pending is not None:
            transcript.add(pending[0], pending[0], 0, pending[1])
        interim.clear()
        try:
            connection.close()
        except Exception:
            pass
        sender.join(timeout=5)


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else ""
    socket_path = sys.argv[2] if len(sys.argv) > 2 else ""
    if not directory or not os.path.isdir(directory) or not socket_path:
        log("usage: fluteos-record-live <recording-dir> <socket>")
        return 2

    key = api_key()
    if not key:
        log("no API key — check features.fluteos.recorder.transcribe.apiKeyFile")
        return 1

    transcript = Transcript(directory)
    interim = Interim(directory)
    interim.clear()

    audio = Audio(socket_path)
    try:
        server = audio.listen()
    except OSError as error:
        log(f"cannot listen on {socket_path}: {error}")
        return 1

    # The meeting ends when systemd stops this unit, not when ffmpeg's
    # connection closes: the encoder drops and reconnects over a long meeting,
    # and treating the first close as the end would transcribe the opening
    # minutes and nothing else.
    def stop(_signum, _frame):
        audio.stopped.set()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    reader = threading.Thread(target=audio.run, args=(server,), daemon=True)
    reader.start()

    url = socket_url()
    first = True
    while not audio.stopped.is_set():
        offset = audio.sent_seconds
        if not first:
            transcript.add_gap(offset)
        try:
            pump(url, key, audio, transcript, interim, offset)
        except Exception as error:
            log(f"connection failed: {error}")
        first = False
        if audio.stopped.is_set():
            break
        time.sleep(RECONNECT_WAIT)

    interim.clear()
    if audio.dropped_frames:
        log(f"dropped {audio.dropped_frames} audio frame(s) while disconnected")
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
