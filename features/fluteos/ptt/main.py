#!/usr/bin/env python3
import signal
import subprocess
import sys
from enum import Enum
from selectors import DefaultSelector, EVENT_READ

from evdev import ecodes

from .audio_ducking import AudioDucker
from .audio_manager import PersistentAudioCapture
from .config import (
    NOTIFY_SEND_PATH,
    WTYPE_PATH,
    ConfigError,
    load_config,
    read_credential,
    resolve_keycode,
)
from .connection_manager import ConnectionManager
from .input import KeyboardMonitor, find_keyboards
from .transcriber import DeepgramTranscriber
from . import transcriber as transcriber_module


class State(Enum):
    IDLE = "idle"
    CONNECTING = "connecting"
    RECORDING = "recording"


state = State.IDLE
audio_ducker = AudioDucker()

# Persistent managers (initialized in main)
connection_manager = None
audio_manager = None


def notify(msg, persistent=False):
    cmd = [NOTIFY_SEND_PATH, "-h", "string:x-canonical-private-synchronous:ptt", "PTT", msg]
    if persistent:
        cmd[3:3] = ["-t", "0"]
    subprocess.run(cmd, check=False)


def set_state(new_state):
    """Single place for state transitions and notifications"""
    global state
    state = new_state
    if state == State.IDLE:
        notify("Done" if transcriber_module.typed_anything else "No speech")
    elif state == State.CONNECTING:
        notify("Connecting...", persistent=True)
    elif state == State.RECORDING:
        notify("Listening...", persistent=True)


def cleanup():
    """Cleanup resources on shutdown"""
    global connection_manager, audio_manager
    print("Shutting down PTT service...", flush=True)

    try:
        audio_ducker.restore()
    except Exception as e:
        print(f"Volume restore error: {e}", flush=True)

    if connection_manager:
        connection_manager.disconnect()

    if audio_manager:
        audio_manager.terminate()


def main():
    global state, connection_manager, audio_manager

    # Setup signal handlers for graceful shutdown
    def signal_handler(signum, frame):
        cleanup()
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    try:
        cfg = load_config()
        hold_key = resolve_keycode(cfg["holdKey"])
        stt = cfg["stt"]
    except ConfigError as e:
        print(f"fluteos-ptt: {e}", file=sys.stderr, flush=True)
        return 1

    print(f"Hold key: {cfg['holdKey']} ({hold_key})", flush=True)

    stt_key = read_credential(stt.get("credential"))
    if not stt_key:
        print(
            "fluteos-ptt: no speech-to-text API key available.\n"
            "  Set features.fluteos.ptt.stt.apiKeyFile to an absolute path on\n"
            "  this machine holding the key.",
            file=sys.stderr,
            flush=True,
        )
        return 1

    # Initialize persistent managers
    audio_manager = PersistentAudioCapture()
    audio_manager.initialize()

    connection_manager = ConnectionManager()

    def on_connected():
        print("Transcription connection ready", flush=True)

    def on_disconnected():
        print("Transcription connection lost", flush=True)

    connection_manager.on_connected = on_connected
    connection_manager.on_disconnected = on_disconnected

    print(f"Connecting ({stt['api']})...", flush=True)
    connection_manager.set_backend(stt, stt_key)
    connection_manager.connect()

    keyboards = {}
    for kb in find_keyboards():
        keyboards[kb.fd] = kb
        print(f"Found keyboard: {kb.path} ({kb.name})", flush=True)

    if not keyboards:
        print("No keyboards found, waiting for devices...", flush=True)

    kb_monitor = KeyboardMonitor()

    sel = DefaultSelector()
    for kb in keyboards.values():
        sel.register(kb, EVENT_READ, data='keyboard')
    sel.register(kb_monitor, EVENT_READ, data='udev')

    current_transcriber = None

    while True:
        events = sel.select(timeout=1.0)

        # Check for timeout/error during recording
        if state in (State.CONNECTING, State.RECORDING) and current_transcriber:
            if current_transcriber.is_timeout():
                try:
                    current_transcriber.stop_streaming()
                except Exception as e:
                    print(f"Auto-stop error: {e}", flush=True)
                current_transcriber = None
                set_state(State.IDLE)
                transcriber_module.typed_anything = False
                continue

            if current_transcriber.is_error():
                current_transcriber.stop_streaming()
                current_transcriber = None
                notify("Connection failed" if state == State.CONNECTING else "Connection lost")
                state = State.IDLE
                transcriber_module.typed_anything = False
                continue

        for key, _ in events:
            if key.data == 'udev':
                event = kb_monitor.poll()
                if event:
                    action, payload = event
                    if action == 'add' and payload:
                        dev = payload
                        if dev.fd not in keyboards:
                            keyboards[dev.fd] = dev
                            sel.register(dev, EVENT_READ, data='keyboard')
                            print(f"Keyboard connected: {dev.path} ({dev.name})", flush=True)
                    elif action == 'remove' and payload:
                        path = payload
                        for fd, kb in list(keyboards.items()):
                            if kb.path == path:
                                try:
                                    sel.unregister(kb)
                                except:
                                    pass
                                del keyboards[fd]
                                print(f"Keyboard disconnected: {path}", flush=True)
                                break
                continue

            if key.data == 'keyboard':
                try:
                    for ev in key.fileobj.read():
                        if ev.type != ecodes.EV_KEY:
                            continue

                        if ev.code == hold_key:
                            print(
                                f"KEY event: value={ev.value} (0=up, 1=down, 2=repeat) from {key.fileobj.path}",
                                flush=True,
                            )
                            if ev.value == 1:  # Key press
                                if state in (State.CONNECTING, State.RECORDING) and current_transcriber:
                                    print("Force stopping previous recording", flush=True)
                                    try:
                                        current_transcriber.stop_streaming()
                                    except:
                                        pass
                                    current_transcriber = None

                                audio_ducker.duck()
                                transcriber_module.typed_anything = False
                                current_transcriber = DeepgramTranscriber()

                                if connection_manager.ensure_connected():
                                    current_transcriber.start_streaming(connection_manager, audio_manager)
                                    set_state(State.RECORDING)
                                else:
                                    set_state(State.CONNECTING)
                                    if connection_manager.wait_for_connection():
                                        current_transcriber.start_streaming(connection_manager, audio_manager)
                                        set_state(State.RECORDING)
                                    else:
                                        notify("Connection failed")
                                        current_transcriber = None
                                        set_state(State.IDLE)

                            elif ev.value == 0:  # Key release
                                audio_ducker.restore()
                                if state in (State.CONNECTING, State.RECORDING):
                                    try:
                                        if current_transcriber:
                                            current_transcriber.stop_streaming()
                                    except Exception as e:
                                        print(f"Stop error: {e}", flush=True)
                                    current_transcriber = None
                                    set_state(State.IDLE)
                                    transcriber_module.typed_anything = False

                except OSError as e:
                    print(f"Device error: {e}", flush=True)
                    kb = key.fileobj
                    try:
                        sel.unregister(kb)
                    except:
                        pass
                    keyboards.pop(kb.fd, None)


if __name__ == "__main__":
    sys.exit(main() or 0)
