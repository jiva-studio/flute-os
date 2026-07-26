import json
import subprocess
import threading
import time

from .config import (
    MAX_RECORDING_SECONDS,
    THREAD_JOIN_TIMEOUT,
    WTYPE_PATH,
)

# How long to wait for Deepgram's final response after we send Finalize.
# Deepgram usually flushes within ~100-200ms; 800ms is a safe upper bound.
FINALIZE_WAIT_TIMEOUT = 0.8

# Global flag for tracking typed text (shared with main)
typed_anything = False


class DeepgramTranscriber:
    """Streams audio to Deepgram for true real-time transcription with interim results.

    Uses external ConnectionManager for WebSocket and AudioManager for audio capture.
    This allows reusing connections between recordings for instant start.
    """

    def __init__(self, behavior: str = "live"):
        # Behaviour, not mode id: what to do with the transcript is declared by
        # features.fluteos.ptt.modes.<m>.behavior. A mode id is a label a
        # downstream user may rename freely, so branching on the string "raw"
        # here would silently turn their renamed dictation mode into a
        # buffering one.
        #   live -> type as it arrives; anything else -> accumulate for main.
        self.behavior = behavior
        self.connection_manager = None
        self.audio_manager = None
        self.should_stop = threading.Event()
        self.has_error = threading.Event()
        self.error = None
        self.text_lock = threading.Lock()
        self.interim_length = 0
        self.interim_text = ""  # Store actual text for diff-based updates
        self.start_time = None
        self.accumulated_text = []  # For LLM modes: accumulate final results
        self.audio_thread = None
        self._original_on_message = None
        # Barrier: when cleared, _handle_message ignores incoming messages.
        # Prevents late WebSocket messages from corrupting state after stop.
        self._accepting_messages = threading.Event()
        # Set by _handle_message when a final arrives — used by stop_streaming
        # to wait for Deepgram's flush after we send Finalize.
        self._finalize_final_received = threading.Event()

    def _delete_chars(self, n) -> bool:
        """Delete n characters using backspace. Returns True on success."""
        if n <= 0:
            return True
        args = [WTYPE_PATH]
        for _ in range(n):
            args.extend(["-k", "BackSpace"])
        try:
            result = subprocess.run(args, check=False)
            return result.returncode == 0
        except Exception as e:
            print(f"wtype delete error: {e}", flush=True)
            return False

    def _type_text(self, text) -> bool:
        """Type text. Returns True on success (or if text is empty)."""
        if not text:
            return True
        try:
            result = subprocess.run([WTYPE_PATH, "--", text], check=False)
            return result.returncode == 0
        except Exception as e:
            print(f"wtype type error: {e}", flush=True)
            return False

    def _find_common_prefix_length(self, old_text, new_text):
        """Find common prefix length between two strings"""
        min_len = min(len(old_text), len(new_text))
        for i in range(min_len):
            if old_text[i] != new_text[i]:
                return i
        return min_len

    def _handle_message(self, message):
        """Handle incoming message from Deepgram."""
        global typed_anything
        try:
            data = json.loads(message)

            if data.get("type") == "Metadata":
                print(f"Deepgram connected: {data}", flush=True)
                return

            channel = data.get("channel", {})
            alternatives = channel.get("alternatives", [])
            if not alternatives:
                return

            transcript = alternatives[0].get("transcript", "").strip()
            is_final = data.get("is_final", False)

            with self.text_lock:
                # Barrier: drop late messages that arrived after stop_streaming.
                # Without this, late finals/interims would corrupt state (typing
                # stale text from a previous session or deleting user's input).
                if not self._accepting_messages.is_set():
                    if transcript:
                        print(f"[late, ignored] final={is_final} {transcript}", flush=True)
                    # Still release any waiter, just in case.
                    if is_final:
                        self._finalize_final_received.set()
                    return

                if not transcript:
                    # Empty final (e.g. Deepgram ack of Finalize with no new text)
                    # still counts as "flush complete" for stop_streaming's waiter.
                    if is_final:
                        self._finalize_final_received.set()
                    return

                if is_final:
                    print(f"[FINAL] {transcript}", flush=True)
                    if self.behavior == "live":
                        # live: type as it arrives, diffing against the interim text.
                        common_len = self._find_common_prefix_length(self.interim_text, transcript)
                        chars_to_delete = len(self.interim_text) - common_len
                        if not self._delete_chars(chars_to_delete):
                            # wtype failed — leave interim_text alone so the next
                            # diff doesn't assume characters were removed.
                            self._finalize_final_received.set()
                            return
                        new_suffix = transcript[common_len:]
                        if self._type_text(new_suffix + " "):
                            self.interim_length = 0
                            self.interim_text = ""
                            typed_anything = True
                    else:
                        # llm/command: buffer; main dispatches it on key release
                        self.accumulated_text.append(transcript)
                        self.interim_length = 0
                        self.interim_text = ""
                        typed_anything = True
                    self._finalize_final_received.set()
                else:
                    print(f"[interim] {transcript}", flush=True)
                    if self.behavior == "live":
                        common_len = self._find_common_prefix_length(self.interim_text, transcript)
                        chars_to_delete = len(self.interim_text) - common_len
                        if not self._delete_chars(chars_to_delete):
                            return
                        new_suffix = transcript[common_len:]
                        if self._type_text(new_suffix):
                            self.interim_text = transcript
                            self.interim_length = len(transcript)
                            typed_anything = True
                    else:
                        # llm/command: track interim text only, as a stop-time fallback.
                        self.interim_text = transcript
                        self.interim_length = len(transcript)

        except Exception as e:
            print(f"Message parse error: {e}", flush=True)

    def start_streaming(self, connection_manager, audio_manager):
        """Start audio streaming using provided connection and audio managers.

        Args:
            connection_manager: ConnectionManager with active connection
            audio_manager: PersistentAudioCapture for audio input

        Returns:
            True if streaming started, False otherwise
        """
        self.connection_manager = connection_manager
        self.audio_manager = audio_manager

        # Reset state
        self.error = None
        self.interim_length = 0
        self.interim_text = ""
        self.accumulated_text = []
        self.should_stop.clear()
        self.has_error.clear()
        self._finalize_final_received.clear()
        self.start_time = time.time()

        # Open the barrier BEFORE registering the handler so we don't miss
        # any messages, and close it in stop_streaming before tearing down.
        self._accepting_messages.set()

        # Hook our message handler into connection_manager
        self._original_on_message = connection_manager.on_message
        connection_manager.on_message = self._handle_message

        # Signal connection manager that we're streaming
        connection_manager.start_streaming()

        # Start audio capture
        audio_manager.start_stream()

        # Start audio streaming thread
        self.audio_thread = threading.Thread(target=self._stream_audio, daemon=True)
        self.audio_thread.start()

        print("Recording started", flush=True)
        return True

    def _stream_audio(self):
        """Stream audio data to Deepgram via connection manager."""
        while not self.should_stop.is_set():
            try:
                # Check timeout
                if time.time() - self.start_time > MAX_RECORDING_SECONDS:
                    print(f"Auto-stop: exceeded {MAX_RECORDING_SECONDS}s", flush=True)
                    self.has_error.set()
                    break

                # Check connection
                if not self.connection_manager.is_streaming():
                    print("Connection lost during streaming", flush=True)
                    self.has_error.set()
                    break

                # Read and send audio
                data = self.audio_manager.read_chunk()
                # Re-check stop flag after the blocking read: without this,
                # one last chunk can leak to Deepgram after stop_streaming
                # sets should_stop, starting a new segment behind Finalize.
                if self.should_stop.is_set():
                    break
                if data:
                    if not self.connection_manager.send_audio(data):
                        print("Failed to send audio", flush=True)
                        self.has_error.set()
                        break

            except Exception as e:
                if not self.should_stop.is_set():
                    print(f"Audio streaming error: {e}", flush=True)
                    self.has_error.set()
                break

    def stop_streaming(self):
        """Stop audio streaming (keeps connection alive for reuse).

        Flow:
          1. Stop audio thread so no new audio goes to Deepgram.
          2. Send Finalize to Deepgram — forces it to flush any pending
             segment and emit a final. Without this, Deepgram holds the
             partial across sessions and dumps it at the start of the
             next recording.
          3. Wait briefly for the final to arrive (handler processes it
             in the current input context).
          4. Close the barrier + restore handler so any further late
             messages are ignored.
          5. Handle fallback (timeout / failed wtype) and tear down.
        """
        self.should_stop.set()

        # 1. Wait for audio thread to finish sending its last chunks.
        if self.audio_thread and self.audio_thread.is_alive():
            self.audio_thread.join(timeout=THREAD_JOIN_TIMEOUT)

        # 2. Ask Deepgram to flush its buffer.
        finalize_sent = False
        if self.connection_manager:
            self._finalize_final_received.clear()
            finalize_sent = self.connection_manager.send_control({"type": "Finalize"})
            if not finalize_sent:
                print("Finalize send failed", flush=True)

        # 3. Wait for the final to arrive and be processed by _handle_message.
        #    Handler runs in the WebSocket thread; the barrier is still open
        #    here so it will process the message normally.
        if finalize_sent:
            got_final = self._finalize_final_received.wait(timeout=FINALIZE_WAIT_TIMEOUT)
            if not got_final:
                print(f"Finalize wait timed out after {FINALIZE_WAIT_TIMEOUT}s", flush=True)

        # 4. Close the barrier + restore handler. From this point on any
        #    late message is ignored (logged as [late, ignored]).
        with self.text_lock:
            self._accepting_messages.clear()

            # 5. Fallback: if interim_text is still non-empty, Deepgram didn't
            #    flush in time. Preserve what we've already typed on screen.
            if self.interim_text:
                if self.behavior == "live":
                    # Text already on screen, just add the trailing space.
                    self._type_text(" ")
                else:
                    # llm/command: include last interim in accumulated text.
                    self.accumulated_text.append(self.interim_text)
            self.interim_length = 0
            self.interim_text = ""

        if self.connection_manager:
            # Restore original message handler
            if self._original_on_message:
                self.connection_manager.on_message = self._original_on_message
            else:
                self.connection_manager.on_message = None

        # Stop audio stream (but keep PyAudio alive)
        if self.audio_manager:
            self.audio_manager.stop_stream()

        # Signal connection manager to resume KeepAlive
        if self.connection_manager:
            self.connection_manager.stop_streaming()

        print("Recording stopped", flush=True)

    # Legacy methods for compatibility
    def start(self):
        """Legacy start method - raises error to catch incorrect usage."""
        raise RuntimeError(
            "DeepgramTranscriber.start() is deprecated. "
            "Use start_streaming(connection_manager, audio_manager) instead."
        )

    def stop(self):
        """Legacy stop method - calls stop_streaming for compatibility."""
        self.stop_streaming()

    def is_timeout(self):
        """Check if recording exceeded timeout"""
        return self.start_time and (time.time() - self.start_time > MAX_RECORDING_SECONDS)

    def is_error(self):
        """Check if an error occurred"""
        return self.has_error.is_set()

    def get_accumulated_text(self) -> str:
        """Get accumulated text for llm/command dispatch"""
        with self.text_lock:
            return " ".join(self.accumulated_text)
