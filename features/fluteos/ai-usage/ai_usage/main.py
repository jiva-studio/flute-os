import json
import os
import sys
from pathlib import Path
from datetime import datetime
import subprocess

CREDENTIALS_FILE = Path.home() / ".claude" / ".credentials.json"
USAGE_API_URL = "https://api.anthropic.com/api/oauth/usage"
OPENROUTER_API_URL = "https://openrouter.ai/api/v1/credits"
MODE_FILE = Path.home() / ".cache" / "ai-usage" / "mode"

# Where an npx/npm install of Claude Code keeps its package.json. Used only to
# read the version for the User-Agent; see claude_code_user_agent().
CLAUDE_CODE_PACKAGE_GLOBS = [
    ".npm/_npx/*/node_modules/@anthropic-ai/claude-code/package.json",
    ".claude/local/node_modules/@anthropic-ai/claude-code/package.json",
    ".local/share/npm/lib/node_modules/@anthropic-ai/claude-code/package.json",
    ".local/state/fnm_multishells/*/lib/node_modules/@anthropic-ai/claude-code/package.json",
]


def get_mode() -> str:
    """Read current mode from state file. Default: claude."""
    try:
        return MODE_FILE.read_text().strip()
    except Exception:
        return "claude"


def output(text: str, tooltip: str = "", css_class: str = ""):
    print(json.dumps({"text": text, "tooltip": tooltip, "class": css_class}))
    sys.exit(0)


def read_secret_file(path: str | None) -> str | None:
    """Read a credential from disk at runtime.

    Secrets are handed to this program as a PATH, never as a value baked into a
    /nix/store script, so reading happens here and only here.
    """
    if not path:
        return None
    try:
        secret = Path(path).expanduser().read_text().strip()
    except Exception:
        return None
    return secret or None


def curl_with_secret_headers(url: str, headers: dict[str, str],
                             secret_headers: dict[str, str]) -> dict | None:
    """GET `url` with curl, keeping secret headers out of the process table.

    Anything on curl's argv is world-readable via /proc, so credentials go in on
    stdin as a curl config file (-K -) instead.
    """
    argv = ["curl", "-s", "-K", "-", url]
    for name, value in headers.items():
        argv += ["-H", f"{name}: {value}"]

    def quote(value: str) -> str:
        return value.replace("\\", "\\\\").replace('"', '\\"')

    config = "".join(
        f'header = "{name}: {quote(value)}"\n'
        for name, value in secret_headers.items()
    )
    try:
        result = subprocess.run(
            argv,
            input=config,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0 and result.stdout:
            return json.loads(result.stdout)
    except Exception:
        pass
    return None


# --- Claude ---

def get_access_token() -> str | None:
    """OAuth token written by Claude Code's login.

    Absence is normal — no Claude Code installed, or never logged in — and is
    reported as "?" by the caller rather than raised.
    """
    try:
        creds = json.loads(CREDENTIALS_FILE.read_text())
        return creds.get("claudeAiOauth", {}).get("accessToken")
    except Exception:
        return None


def detect_claude_code_version() -> str | None:
    """Version of the locally installed Claude Code, if it can be found."""
    home = Path.home()
    candidates = []
    for pattern in CLAUDE_CODE_PACKAGE_GLOBS:
        try:
            candidates += list(home.glob(pattern))
        except Exception:
            continue
    for package_json in sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True):
        try:
            version = json.loads(package_json.read_text()).get("version")
        except Exception:
            continue
        if version:
            return str(version)
    return None


def claude_user_agent() -> str | None:
    """User-Agent for the OAuth usage endpoint.

    This is Claude Code's own endpoint, so it wants Claude Code's UA. A literal
    "claude-code/<version>" string rots with every release and silently starts
    lying, so the version is read from the installed package instead, with
    CLAUDE_USAGE_USER_AGENT as an escape hatch. Undiscoverable → no UA header at
    all (curl sends its own) rather than a stale invention.
    """
    override = os.environ.get("CLAUDE_USAGE_USER_AGENT")
    if override:
        return override
    version = detect_claude_code_version()
    return f"claude-code/{version}" if version else None


def fetch_claude_usage() -> dict | None:
    token = get_access_token()
    if not token:
        return None
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "anthropic-beta": "oauth-2025-04-20",
    }
    user_agent = claude_user_agent()
    if user_agent:
        headers["User-Agent"] = user_agent
    return curl_with_secret_headers(
        USAGE_API_URL,
        headers,
        {"Authorization": f"Bearer {token}"},
    )


def format_reset_time(iso_time: str | None) -> str:
    if not iso_time:
        return "?"
    try:
        reset = datetime.fromisoformat(iso_time.replace("Z", "+00:00"))
        now = datetime.now().astimezone()
        delta = reset - now
        hours = int(delta.total_seconds() // 3600)
        minutes = int((delta.total_seconds() % 3600) // 60)
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes}m"
    except Exception:
        return "?"


def show_claude():
    # Told apart on purpose: "never logged in" is a setup step the user can act
    # on, "fetch failed" is transient.
    if not get_access_token():
        output(
            "<span size='16pt' rise='-2pt'>󰚩</span> ?",
            "Claude: not signed in\n"
            f"No OAuth token in {CREDENTIALS_FILE}\n"
            "Log in with Claude Code, or click to switch to OpenRouter",
            "error",
        )

    usage = fetch_claude_usage()

    if not usage:
        output("<span size='16pt' rise='-2pt'>󰚩</span> ?", "Claude: Unable to fetch usage", "error")

    five_hour = usage.get("five_hour") or {}
    seven_day = usage.get("seven_day") or {}

    pct_5h = int(five_hour.get("utilization", 0))
    pct_7d = int(seven_day.get("utilization", 0))
    reset_5h = format_reset_time(five_hour.get("resets_at"))

    if pct_5h >= 90:
        css = "critical"
    elif pct_5h >= 50:
        css = "warning"
    else:
        css = "normal"

    text = f"<span size='16pt' rise='-2pt'>󰚩</span> {pct_5h}% ({reset_5h})"

    tooltip_lines = [
        "Claude Usage (click to switch)",
        f"Session: {pct_5h}% (resets in {reset_5h})",
        f"Weekly: {pct_7d}%",
    ]

    sonnet = usage.get("seven_day_sonnet") or {}
    if sonnet.get("utilization") is not None:
        tooltip_lines.append(f"Sonnet: {int(sonnet['utilization'])}%")

    output(text, "\n".join(tooltip_lines), css)


# --- OpenRouter ---

def get_openrouter_key() -> str | None:
    """OpenRouter key, read from disk at runtime.

    OPENROUTER_API_KEY_FILE holds a PATH — set from
    features.fluteos.claude-usage.openrouterApiKeyFile — so the key itself is
    never baked into a /nix/store script. OPENROUTER_API_KEY is still honoured
    for anyone driving this reporter by hand.
    """
    key = read_secret_file(os.environ.get("OPENROUTER_API_KEY_FILE"))
    if key:
        return key
    env_key = (os.environ.get("OPENROUTER_API_KEY") or "").strip()
    return env_key or None


def fetch_openrouter_credits() -> dict | None:
    api_key = get_openrouter_key()
    if not api_key:
        return None
    return curl_with_secret_headers(
        OPENROUTER_API_URL,
        {"Accept": "application/json"},
        {"Authorization": f"Bearer {api_key}"},
    )


def show_openrouter():
    # Same split as Claude: a missing key is a configuration step, not a network
    # blip, and saying which is which saves the user a debugging session.
    if not get_openrouter_key():
        key_file = os.environ.get("OPENROUTER_API_KEY_FILE") or "<unset>"
        output(
            "<span size='16pt' rise='-2pt'>󰚩</span> ?",
            "OpenRouter: no API key configured\n"
            f"Key file: {key_file}\n"
            "Set features.fluteos.claude-usage.openrouterApiKeyFile to a readable "
            "file holding the key",
            "error",
        )

    response = fetch_openrouter_credits()

    if not response:
        output("<span size='16pt' rise='-2pt'>󰚩</span> ?", "OpenRouter: Unable to fetch usage", "error")

    data = response.get("data", {})
    total_credits = data.get("total_credits", 0)
    total_usage = data.get("total_usage", 0)
    balance = total_credits - total_usage

    if balance < 1:
        css = "critical"
    elif balance < 5:
        css = "warning"
    else:
        css = "normal"

    text = f"<span size='16pt' rise='-2pt'>󰚩</span> ${balance:.2f}"

    tooltip_lines = [
        "OpenRouter (click to switch)",
        f"Balance: ${balance:.2f}",
        f"Used: ${total_usage:.2f}",
        f"Total: ${total_credits:.2f}",
    ]

    output(text, "\n".join(tooltip_lines), css)


# --- Main ---

def main():
    mode = get_mode()
    if mode == "openrouter":
        show_openrouter()
    else:
        show_claude()


if __name__ == "__main__":
    main()
