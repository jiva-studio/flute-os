"""Persistent audio capture manager for PTT service.

Keeps PyAudio initialized to avoid ~100-200ms initialization delay on each recording.
"""

import pyaudio

from .config import CHUNK_SIZE, SAMPLE_RATE


class PersistentAudioCapture:
    """Manages PyAudio instance and audio stream lifecycle.

    PyAudio is initialized once at startup and kept alive.
    Audio streams are started/stopped without reinitializing PyAudio.
    """

    def __init__(self):
        self.audio = None
        self.stream = None
        self._initialized = False

    def initialize(self):
        """Initialize PyAudio instance (call once at startup)."""
        if self._initialized:
            return

        self.audio = pyaudio.PyAudio()
        self._initialized = True
        print("PyAudio initialized", flush=True)

    def start_stream(self):
        """Start audio capture stream.

        Returns the stream for reading audio data.
        PyAudio must be initialized first.
        """
        if not self._initialized:
            self.initialize()

        if self.stream is not None:
            self.stop_stream()

        self.stream = self.audio.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=SAMPLE_RATE,
            input=True,
            frames_per_buffer=CHUNK_SIZE,
        )
        return self.stream

    def stop_stream(self):
        """Stop and close audio stream (keeps PyAudio alive)."""
        if self.stream is not None:
            try:
                self.stream.stop_stream()
                self.stream.close()
            except Exception as e:
                print(f"Stream close error: {e}", flush=True)
            self.stream = None

    def read_chunk(self):
        """Read a chunk of audio data from the stream.

        Returns None if stream is not active.
        """
        if self.stream is None:
            return None
        try:
            return self.stream.read(CHUNK_SIZE, exception_on_overflow=False)
        except Exception as e:
            print(f"Audio read error: {e}", flush=True)
            return None

    def terminate(self):
        """Terminate PyAudio completely (call on service shutdown)."""
        self.stop_stream()

        if self.audio is not None:
            try:
                self.audio.terminate()
            except Exception as e:
                print(f"PyAudio terminate error: {e}", flush=True)
            self.audio = None

        self._initialized = False
        print("PyAudio terminated", flush=True)

    def is_active(self):
        """Check if audio stream is currently active."""
        return self.stream is not None

    def __enter__(self):
        self.initialize()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.terminate()
        return False
