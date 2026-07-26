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
    get_current_mode,
    get_next_mode,
    load_config,
    read_credential,
    resolve_keycode,
    resolve_keycodes,
    set_current_mode,
)
from .connection_manager import ConnectionManager
from .input import KeyboardMonitor, find_keyboards
from .llm import LlmUnconfigured, process_with_llm
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


def type_text(text: str) -> None:
    """Type text using wtype"""
    if text:
        subprocess.run([WTYPE_PATH, "--", text], check=False)


def dispatch_transcript(transcriber: DeepgramTranscriber, mode: str, cfg: dict) -> None:
    """Hand a buffered transcript to the mode's sink (LLM or command).

    Dispatch is by `behavior`, declared per mode in Nix — never by mode id, so a
    renamed or newly added mode behaves as configured.
    """
    accumulated = transcriber.get_accumulated_text()
    if not accumulated:
        return

    mode_config = cfg["modes"][mode]
    behavior = mode_config["behavior"]
    mode_name = mode_config.get("name") or mode

    if behavior == "command":
        # Hand the phrase to the configured command sink, type nothing.
        # Dispatched detached — the sink may consult an LLM and notify on its
        # own, so blocking here would freeze PTT and let the idle notification
        # overwrite the sink's answer.
        argv = mode_config.get("command")
        if not argv:
            # Unreachable via Nix (an assertion rejects it), but a hand-written
            # config file should still say what is wrong.
            notify(f"{mode_name}: no command sink configured")
            return
        notify(f"Command: {accumulated}")
        # Keeps the idle transition from reporting "No speech" for a phrase
        # that was in fact dispatched.
        transcriber_module.typed_anything = True
        subprocess.Popen([*argv, accumulated])
        return

    if behavior != "llm":
        return

    prompt = mode_config.get("prompt")
    if not prompt:
        notify(f"{mode_name}: no prompt configured")
        return

    llm = mode_config["llm"]
    api_key = read_credential(llm.get("credential"))
    if not api_key:
        # Degrade per capability: the STT key got us the transcript, only the
        # LLM half is missing. Say so precisely instead of failing opaquely.
        print(f"Mode '{mode}': LLM key not configured", flush=True)
        notify(f"{mode_name}: LLM key not configured")
        return

    notify(f"Processing: {mode_name}...", persistent=True)

    try:
        result = process_with_llm(accumulated, prompt, llm, api_key)
        type_text(result + " ")
    except LlmUnconfigured as e:
        print(f"LLM not configured: {e}", flush=True)
        notify(f"{mode_name}: LLM key not configured")
    except Exception as e:
        print(f"LLM processing error: {e}", flush=True)
        notify(f"LLM error: {e}")


def cleanup():
    """Cleanup resources on shutdown"""
    global connection_manager, audio_manager
    print("Shutting down PTT service...", flush=True)

    # First: give the user their volume back. AudioDucker no longer installs its
    # own SIGTERM handler (this handler would have overwritten it), so a killed
    # service used to leave the sink ducked at 20% forever.
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

    # Load configuration. A failure here is fatal and explicit: there is no
    # built-in mode table to fall back on (see config.py).
    try:
        cfg = load_config()
        hold_key = resolve_keycode(cfg["holdKey"])
        cycle_keys = resolve_keycodes(cfg.get("cycleKeys"))
    except ConfigError as e:
        print(f"fluteos-ptt: {e}", file=sys.stderr, flush=True)
        return 1

    modes = cfg["modes"]
    print(f"Loaded modes: {list(modes)} (cycle order: {cfg['order']})", flush=True)
    print(f"Hold key: {cfg['holdKey']} ({hold_key})", flush=True)

    # Capability check. Without an STT key nothing can be transcribed, in any
    # mode, so refuse to run instead of sitting idle and silently doing nothing
    # every time the key is pressed. Missing LLM keys are NOT fatal: plain
    # dictation still works and only those modes report themselves unconfigured.
    usable = [m for m, mc in modes.items() if read_credential(mc["stt"].get("credential"))]
    if not usable:
        print(
            "fluteos-ptt: no speech-to-text API key available for any mode.\n"
            "  Set features.fluteos.ptt.stt.apiKeyFile to an absolute path on\n"
            "  this machine holding the key, and make sure that file exists and\n"
            "  is readable by this user (it is passed to the service as a\n"
            "  systemd credential, never copied into /nix/store).",
            file=sys.stderr,
            flush=True,
        )
        return 1
    for mode in modes:
        if mode not in usable:
            print(f"Mode '{mode}': no STT key — unavailable", flush=True)

    # Initialize persistent managers
    audio_manager = PersistentAudioCapture()
    audio_manager.initialize()

    connection_manager = ConnectionManager()

    # Callback for when connection is established
    def on_connected():
        print("Transcription connection ready", flush=True)

    def on_disconnected():
        print("Transcription connection lost", flush=True)

    connection_manager.on_connected = on_connected
    connection_manager.on_disconnected = on_disconnected

    # Warm the connection for the mode we will start in, so the first press is
    # instant. Other modes may use a different backend; set_backend reconnects.
    startup_mode = get_current_mode(cfg)
    startup_stt = modes[startup_mode]["stt"]
    startup_key = read_credential(startup_stt.get("credential"))
    if startup_key:
        print(f"Connecting ({startup_stt['api']}, mode '{startup_mode}')...", flush=True)
        connection_manager.set_backend(startup_stt, startup_key)
        connection_manager.connect()

    # Dict: fd -> InputDevice
    keyboards = {}
    for kb in find_keyboards():
        keyboards[kb.fd] = kb
        print(f"Found keyboard: {kb.path} ({kb.name})", flush=True)

    if not keyboards:
        print("No keyboards found, waiting for devices...", flush=True)

    # udev monitor for hotplug
    kb_monitor = KeyboardMonitor()

    sel = DefaultSelector()
    for kb in keyboards.values():
        sel.register(kb, EVENT_READ, data='keyboard')
    sel.register(kb_monitor, EVENT_READ, data='udev')

    current_transcriber = None
    current_mode = None
    alt_pressed = False

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
            # Handle udev events
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

            # Handle keyboard events
            if key.data == 'keyboard':
                try:
                    for ev in key.fileobj.read():
                        if ev.type != ecodes.EV_KEY:
                            continue

                        # Hold key (configured by evdev name, resolved above)
                        if ev.code == hold_key:
                            print(
                                f"KEY event: value={ev.value} (0=up, 1=down, 2=repeat) from {key.fileobj.path}",
                                flush=True,
                            )
                            if ev.value == 1:  # Key press
                                alt_pressed = True

                                # Stop any previous recording
                                if state in (State.CONNECTING, State.RECORDING) and current_transcriber:
                                    print("Force stopping previous recording", flush=True)
                                    try:
                                        current_transcriber.stop_streaming()
                                    except:
                                        pass
                                    current_transcriber = None

                                # Get current mode before starting
                                current_mode = get_current_mode(cfg)
                                mode_config = modes[current_mode]
                                print(f"Starting recording in mode: {current_mode}", flush=True)

                                # This mode's STT backend + its key. Missing key
                                # is reported per mode; other modes keep working.
                                stt = mode_config["stt"]
                                stt_key = read_credential(stt.get("credential"))
                                if not stt_key:
                                    notify(f"{mode_config.get('name') or current_mode}: STT key not configured")
                                    current_mode = None
                                    continue

                                audio_ducker.duck()
                                connection_manager.set_backend(stt, stt_key)

                                transcriber_module.typed_anything = False
                                current_transcriber = DeepgramTranscriber(
                                    behavior=mode_config["behavior"]
                                )

                                # Ensure connection is ready
                                if connection_manager.ensure_connected():
                                    # Connection ready - start immediately
                                    current_transcriber.start_streaming(connection_manager, audio_manager)
                                    set_state(State.RECORDING)
                                else:
                                    # Need to wait for connection
                                    set_state(State.CONNECTING)
                                    # Wait in background and start when ready
                                    if connection_manager.wait_for_connection():
                                        current_transcriber.start_streaming(connection_manager, audio_manager)
                                        set_state(State.RECORDING)
                                    else:
                                        notify("Connection failed")
                                        current_transcriber = None
                                        set_state(State.IDLE)

                            elif ev.value == 0:  # Key release
                                alt_pressed = False
                                audio_ducker.restore()
                                if state in (State.CONNECTING, State.RECORDING):
                                    try:
                                        if current_transcriber:
                                            current_transcriber.stop_streaming()
                                            # Anything that buffers instead of
                                            # typing live needs dispatching now.
                                            if current_mode and modes[current_mode]["behavior"] != "live":
                                                dispatch_transcript(current_transcriber, current_mode, cfg)
                                    except Exception as e:
                                        print(f"Stop error: {e}", flush=True)
                                    current_transcriber = None
                                    current_mode = None
                                    set_state(State.IDLE)
                                    transcriber_module.typed_anything = False

                        # Cycle keys (configured by evdev name), while held
                        elif ev.code in cycle_keys:
                            if ev.value == 1 and alt_pressed:
                                new_mode = get_next_mode(current_mode or get_current_mode(cfg), cfg)
                                set_current_mode(new_mode)
                                current_mode = new_mode
                                mode_config = modes[new_mode]

                                # Mid-recording switch: the transcriber must
                                # follow the new mode's behaviour, not its id.
                                if current_transcriber:
                                    current_transcriber.behavior = mode_config["behavior"]

                                mode_name = mode_config.get("name") or new_mode
                                mode_icon = mode_config.get("icon") or ""
                                notify(f"{mode_icon} {mode_name}", persistent=state in (State.CONNECTING, State.RECORDING))
                                print(f"Mode switched to: {new_mode}", flush=True)

                                # Signal waybar to update PTT widget
                                subprocess.run(["pkill", "-SIGRTMIN+11", "waybar"], check=False)

                except OSError as e:
                    print(f"Device error: {e}", flush=True)
                    kb = key.fileobj
                    try:
                        sel.unregister(kb)
                    except:
                        pass
                    keyboards.pop(kb.fd, None)


if __name__ == "__main__":
    # main() returns a non-zero code for configuration/capability failures, so
    # systemd reports the service as failed instead of "started, doing nothing".
    sys.exit(main() or 0)
