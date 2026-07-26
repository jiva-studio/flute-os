"""Runtime configuration for fluteos-ptt.

Everything user-visible — keys, modes, prompts, backends — comes from the
Nix-generated JSON pointed at by $FLUTEOS_PTT_CONFIG.

There is deliberately NO built-in mode table. A second copy of the modes here
would drift from the Nix one (it already had: the fallback's translate prompt
differed from the declared one), and the drift is invisible until the day the
config is missing — at which point every downstream user silently inherits the
prompts and language of whoever wrote the fallback. A missing or malformed
config is therefore a hard, loud failure.

API keys are read from $CREDENTIALS_DIRECTORY (systemd LoadCredential) at
runtime. They are never baked into the store, the unit file, or the environment.
"""
import json
import os
from pathlib import Path
from urllib.parse import urlencode

from evdev import ecodes

# Paths from Nix (via environment)
WTYPE_PATH = os.environ.get("WTYPE_PATH", "wtype")
NOTIFY_SEND_PATH = os.environ.get("NOTIFY_SEND_PATH", "notify-send")

CONFIG_ENV = "FLUTEOS_PTT_CONFIG"

# Audio/transport constants. Not configuration: these are properties of the
# capture pipeline, identical on every machine.
SAMPLE_RATE = 16000
CHUNK_SIZE = 1600  # 100ms chunks at 16kHz
MAX_RECORDING_SECONDS = 300  # Auto-stop if key release missed (5 min)
WS_CONNECT_TIMEOUT = 5
THREAD_JOIN_TIMEOUT = 1.0

# Persistent connection settings
KEEPALIVE_INTERVAL = 5.0      # seconds between KeepAlive messages
MAX_RECONNECT_ATTEMPTS = 3    # reconnect attempts before giving up
IDLE_TIMEOUT = 300            # 5 minutes - close connection if unused

# PTT mode cache (which mode the user last cycled to)
MODE_FILE = Path.home() / ".cache" / "ptt" / "mode"


class ConfigError(RuntimeError):
    """Configuration is absent, unreadable or structurally wrong.

    Always fatal: main() prints the message and exits non-zero rather than
    guessing at a default.
    """


def load_config() -> dict:
    """Load and validate the generated config. Raises ConfigError."""
    path = os.environ.get(CONFIG_ENV)
    if not path:
        raise ConfigError(
            f"{CONFIG_ENV} is not set. fluteos-ptt is configured entirely from "
            "the generated JSON and has no built-in defaults; run it from the "
            "fluteos-ptt.service unit, which sets this variable."
        )

    try:
        raw = Path(path).read_text()
    except OSError as e:
        raise ConfigError(f"cannot read {CONFIG_ENV}={path}: {e}") from e

    try:
        data = json.loads(raw)
    except ValueError as e:
        raise ConfigError(f"{path} is not valid JSON: {e}") from e

    modes = data.get("modes")
    if not isinstance(modes, dict) or not modes:
        raise ConfigError(f"{path}: 'modes' must be a non-empty object")

    order = data.get("order")
    if not isinstance(order, list) or not order:
        raise ConfigError(f"{path}: 'order' must be a non-empty list")

    unknown = [m for m in order if m not in modes]
    if unknown:
        raise ConfigError(f"{path}: 'order' names undeclared modes: {', '.join(unknown)}")

    default_mode = data.get("defaultMode")
    if default_mode not in modes:
        raise ConfigError(f"{path}: 'defaultMode' ({default_mode!r}) is not a declared mode")

    if not data.get("holdKey"):
        raise ConfigError(f"{path}: 'holdKey' is missing")

    return data


def resolve_keycode(name: str) -> int:
    """Map an evdev key NAME (KEY_RIGHTALT) to its raw code.

    Names, not scancodes, are the configuration surface: a scancode in a config
    file is unreadable and unverifiable, whereas an unknown name fails here with
    a message that says which name was wrong.
    """
    code = ecodes.ecodes.get(name)
    if code is None:
        raise ConfigError(
            f"unknown evdev key name {name!r}; expected a name from "
            "linux/input-event-codes.h such as KEY_RIGHTALT"
        )
    return code


def resolve_keycodes(names: list) -> set:
    return {resolve_keycode(n) for n in names or []}


def read_credential(name) -> str | None:
    """Read an API key from the systemd credentials directory.

    Returns None when the credential was not declared, the directory is absent
    (running outside the unit), or the file is empty — which is what a missing
    key file looks like, because the unit pairs every LoadCredential= with an
    empty SetCredential= default so that a missing key does not prevent the
    service from starting at all.
    """
    if not name:
        return None

    directory = os.environ.get("CREDENTIALS_DIRECTORY") or os.environ.get(
        "FLUTEOS_PTT_CREDENTIALS_DIR"
    )
    if not directory:
        return None

    try:
        value = (Path(directory) / name).read_text().strip()
    except OSError:
        return None

    return value or None


def stt_ws_url(stt: dict) -> str:
    """Build the streaming STT WebSocket URL from a resolved backend config."""
    api = stt.get("api")
    if api != "deepgram":
        raise ConfigError(
            f"unsupported stt.api {api!r}; this build implements the Deepgram "
            "streaming shape only (point stt.endpoint at a compatible proxy if "
            "needed)"
        )

    params = {
        "model": stt["model"],
        "interim_results": "true",
        "encoding": "linear16",
        "sample_rate": str(SAMPLE_RATE),
        "channels": "1",
        "punctuate": "true",
    }
    language = stt.get("language")
    if language:
        params["language"] = language

    return f"{stt['endpoint']}?{urlencode(params)}"


def stt_auth_header(stt: dict, api_key: str) -> dict:
    api = stt.get("api")
    if api != "deepgram":
        raise ConfigError(f"unsupported stt.api {api!r}")
    return {"Authorization": f"Token {api_key}"}


def get_current_mode(cfg: dict) -> str:
    """Read the cached mode, falling back to the CONFIGURED default.

    A cached mode that no longer exists (renamed or removed in the config) is
    not an error — but the replacement comes from the config, not from a
    hardcoded name.
    """
    default = cfg["defaultMode"]
    if MODE_FILE.exists():
        try:
            mode = MODE_FILE.read_text().strip()
        except OSError:
            return default
        if mode in cfg["modes"]:
            return mode
    return default


def set_current_mode(mode: str) -> None:
    """Write current mode to cache file"""
    MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
    MODE_FILE.write_text(mode)


def get_next_mode(current: str, cfg: dict) -> str:
    """Get next mode in cycle"""
    order = cfg["order"]
    try:
        return order[(order.index(current) + 1) % len(order)]
    except ValueError:
        return order[0]
