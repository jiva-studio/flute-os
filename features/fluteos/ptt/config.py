"""Runtime configuration for fluteos-ptt.

Reads $FLUTEOS_PTT_CONFIG for hold key and STT backend settings.
API keys are read from $CREDENTIALS_DIRECTORY at runtime.
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

# Audio/transport constants
SAMPLE_RATE = 16000
CHUNK_SIZE = 1600  # 100ms chunks at 16kHz
MAX_RECORDING_SECONDS = 300  # Auto-stop if key release missed (5 min)
WS_CONNECT_TIMEOUT = 5
THREAD_JOIN_TIMEOUT = 1.0

# Persistent connection settings
KEEPALIVE_INTERVAL = 5.0      # seconds between KeepAlive messages
MAX_RECONNECT_ATTEMPTS = 3    # reconnect attempts before giving up
IDLE_TIMEOUT = 300            # 5 minutes - close connection if unused


class ConfigError(RuntimeError):
    """Configuration is absent, unreadable or structurally wrong."""


def load_config() -> dict:
    """Load and validate the generated config. Raises ConfigError."""
    path = os.environ.get(CONFIG_ENV)
    if not path:
        raise ConfigError(
            f"{CONFIG_ENV} is not set. Run fluteos-ptt from the "
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

    if not data.get("stt") or not isinstance(data["stt"], dict):
        raise ConfigError(f"{path}: 'stt' must be a valid object")

    if not data.get("holdKey"):
        raise ConfigError(f"{path}: 'holdKey' is missing")

    return data


def resolve_keycode(name: str) -> int:
    """Map an evdev key NAME (KEY_RIGHTALT) to its raw code."""
    code = ecodes.ecodes.get(name)
    if code is None:
        raise ConfigError(
            f"unknown evdev key name {name!r}; expected a name from "
            "linux/input-event-codes.h such as KEY_RIGHTALT"
        )
    return code


def read_credential(name) -> str | None:
    """Read an API key from the systemd credentials directory."""
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
    """Build the streaming STT WebSocket URL from resolved backend config."""
    api = stt.get("api")
    if api != "deepgram":
        raise ConfigError(
            f"unsupported stt.api {api!r}; this build implements the Deepgram "
            "streaming shape only"
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
