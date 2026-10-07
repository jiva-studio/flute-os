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
FINALIZE_WAIT_TIMEOUT = 0.8

# Global flag for tracking typed text (shared with main)
typed_anything = False


class DeepgramTranscriber:
    """Streams audio to Deepgram for real-time transcription with interim results.

    Types directly into the focused window via wtype as text arrives (RAW mode).
    """

    def __init__(self):
        self.connection_manager = None
        self.audio_manager = None
        self.should_stop = threading.Event()
        self.has_error = threading.Event()
        self.error = None
        self.text_lock = threading.Lock()
        self.interim_length = 0
        self.interim_text = ""
        self.start_time = None
        self.audio_thread = None
        self._original_on_message = None
        self._accepting_messages = threading.Event()
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
                if not self._accepting_messages.is_set():
                    if transcript:
                        print(f"[late, ignored] final={is_final} {transcript}", flush=True)
                    if is_final:
                        self._finalize_final_received.set()
                    return

                if not transcript:
                    if is_final:
                        self._finalize_final_received.set()
                    return

                if is_final:
                    print(f"[FINAL] {transcript}", flush=True)
                    common_len = self._find_common_prefix_length(self.interim_text, transcript)
                    chars_to_delete = len(self.interim_text) - common_len
                    if not self._delete_chars(chars_to_delete):
                        self._finalize_final_received.set()
                        return
                    new_suffix = transcript[common_len:]
                    if self._type_text(new_suffix + " "):
                        self.interim_length = 0
                        self.interim_text = ""
                        typed_anything = True
                    self._finalize_final_received.set()
                else:
                    print(f"[interim] {transcript}", flush=True)
                    common_len = self._find_common_prefix_length(self.interim_text, transcript)
                    chars_to_delete = len(self.interim_text) - common_len
                    if not self._delete_chars(chars_to_delete):
                        return
                    new_suffix = transcript[common_len:]
                    if self._type_text(new_suffix):
                        self.interim_text = transcript
                        self.interim_length = len(transcript)
                        typed_anything = True

        except Exception as e:
            print(f"Message parse error: {e}", flush=True)

    def start_streaming(self, connection_manager, audio_manager):
        """Start audio streaming using provided connection and audio managers."""
        self.connection_manager = connection_manager
        self.audio_manager = audio_manager

        self.error = None
        self.interim_length = 0
        self.interim_text = ""
        self.should_stop.clear()
        self.has_error.clear()
        self._finalize_final_received.clear()
        self.start_time = time.time()

        self._accepting_messages.set()

        self._original_on_message = connection_manager.on_message
        connection_manager.on_message = self._handle_message

        connection_manager.start_streaming()
        audio_manager.start_stream()

        self.audio_thread = threading.Thread(target=self._stream_audio, daemon=True)
        self.audio_thread.start()

        print("Recording started", flush=True)
        return True

    def _stream_audio(self):
        """Stream audio data to Deepgram via connection manager."""
        while not self.should_stop.is_set():
            try:
                if time.time() - self.start_time > MAX_RECORDING_SECONDS:
                    print(f"Auto-stop: exceeded {MAX_RECORDING_SECONDS}s", flush=True)
                    self.has_error.set()
                    break

                if not self.connection_manager.is_streaming():
                    print("Connection lost during streaming", flush=True)
                    self.has_error.set()
                    break

                data = self.audio_manager.read_chunk()
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
        """Stop audio streaming."""
        self.should_stop.set()

        if self.audio_thread and self.audio_thread.is_alive():
            self.audio_thread.join(timeout=THREAD_JOIN_TIMEOUT)

        finalize_sent = False
        if self.connection_manager:
            self._finalize_final_received.clear()
            finalize_sent = self.connection_manager.send_control({"type": "Finalize"})
            if not finalize_sent:
                print("Finalize send failed", flush=True)

        if finalize_sent:
            got_final = self._finalize_final_received.wait(timeout=FINALIZE_WAIT_TIMEOUT)
            if not got_final:
                print(f"Finalize wait timed out after {FINALIZE_WAIT_TIMEOUT}s", flush=True)

        with self.text_lock:
            self._accepting_messages.clear()
            if self.interim_text:
                self._type_text(" ")
            self.interim_length = 0
            self.interim_text = ""

        if self.connection_manager:
            if self._original_on_message:
                self.connection_manager.on_message = self._original_on_message
            else:
                self.connection_manager.on_message = None

        if self.audio_manager:
            self.audio_manager.stop_stream()

        if self.connection_manager:
            self.connection_manager.stop_streaming()

        print("Recording stopped", flush=True)

    def is_timeout(self):
        return self.start_time and (time.time() - self.start_time > MAX_RECORDING_SECONDS)

    def is_error(self):
        return self.has_error.is_set()
