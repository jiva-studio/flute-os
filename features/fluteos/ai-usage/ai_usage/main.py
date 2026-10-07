"""Report what is left on every AI coding plan, in one line.

The widget used to show ONE provider and cycle through the rest on click, which
meant the bar could only ever answer "what is left on the thing I last clicked".
Every provider is reported at once now, each behind a three-letter label, and
the click that used to switch providers is gone with the toggle.

Providers are fetched in parallel: five serial network calls at up to ten
seconds each would blow past any sane poll, and they have nothing to say to one
another.
"""

import json
import os
import re
import sys
import subprocess
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

CREDENTIALS_FILE = Path.home() / ".claude" / ".credentials.json"
USAGE_API_URL = "https://api.anthropic.com/api/oauth/usage"
OPENROUTER_API_URL = "https://openrouter.ai/api/v1/credits"
ZAI_QUOTA_API_URL = "https://api.z.ai/api/monitor/usage/quota/limit"

CODEX_SESSIONS_DIR = Path.home() / ".codex" / "sessions"
# How many rollout files back to look for a rate-limit record. The newest
# session is often a fresh one that has not made a request yet, so stopping at
# the first file would report "?" for a plan that is perfectly readable.
CODEX_ROLLOUT_SCAN = 8
# Only the tail of a rollout is read: these grow to megabytes over a long
# session and the record we want is the most recent one in the file.
CODEX_TAIL_BYTES = 512 * 1024

ANTIGRAVITY_RPC_PATH = (
    "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
)

PROVIDERS_FILE = os.environ.get("PROVIDERS_FILE")

LEGACY_PROVIDERS = [
    {"id": "claude", "backend": "claude-oauth", "name": "Claude", "label": "CLD", "order": 10},
    {"id": "openrouter", "backend": "openrouter", "name": "OpenRouter", "label": "ORT", "order": 20},
]

CLAUDE_CODE_PACKAGE_GLOBS = [
    ".npm/_npx/*/node_modules/@anthropic-ai/claude-code/package.json",
    ".claude/local/node_modules/@anthropic-ai/claude-code/package.json",
    ".local/share/npm/lib/node_modules/@anthropic-ai/claude-code/package.json",
    ".local/state/fnm_multishells/*/lib/node_modules/@anthropic-ai/claude-code/package.json",
]


# --- provider catalogue ---

def load_providers() -> list[dict]:
    """Every provider to report on, in bar order."""
    try:
        raw = json.loads(Path(PROVIDERS_FILE).read_text())
    except Exception:
        return LEGACY_PROVIDERS
    providers = [dict(entry, id=pid) for pid, entry in raw.items()]
    if not providers:
        return LEGACY_PROVIDERS
    return sorted(providers, key=lambda p: (p.get("order", 50), p.get("name", p["id"])))


def label_of(provider: dict) -> str:
    """The three letters this provider wears on the bar."""
    return (provider.get("label") or provider["id"][:3]).upper()


# --- result plumbing ---

def result(provider, body, pct=None, level="normal", lines=None) -> dict:
    """One provider's answer.

    A backend never prints or exits: with every provider on the bar at once, one
    that cannot be reached must not take the other four down with it.
    """
    return {
        "label": label_of(provider),
        "name": provider.get("name") or provider["id"],
        "body": body,
        "pct": pct,
        "level": level,
        "lines": lines or [],
    }


def failed(provider, *lines) -> dict:
    return result(provider, "?", level="error", lines=list(lines))


def usage_class(pct: float) -> str:
    if pct >= 90:
        return "critical"
    if pct >= 50:
        return "warning"
    return "normal"


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


def provider_key(provider: dict) -> str | None:
    return read_secret_file(provider.get("apiKeyFile"))


def curl_json(url, headers=None, secret_headers=None, data=None, insecure=False):
    """POST/GET `url` with curl, keeping secret headers out of the process table.

    Anything on curl's argv is world-readable via /proc, so credentials go in on
    stdin as a curl config file (-K -) instead.
    """
    argv = ["curl", "-s", "-K", "-", url]
    if insecure:
        argv.insert(1, "-k")
    for name, value in (headers or {}).items():
        argv += ["-H", f"{name}: {value}"]
    if data is not None:
        argv += ["-X", "POST", "--data-binary", data]

    def quote(value: str) -> str:
        return value.replace("\\", "\\\\").replace('"', '\\"')

    config = "".join(
        f'header = "{name}: {quote(value)}"\n'
        for name, value in (secret_headers or {}).items()
    )
    try:
        done = subprocess.run(argv, input=config, capture_output=True,
                              text=True, timeout=10)
        if done.returncode == 0 and done.stdout:
            return json.loads(done.stdout)
    except Exception:
        pass
    return None


# --- time formatting ---

def format_reset_time(iso_time: str | None) -> str:
    if not iso_time:
        return "?"
    try:
        reset = datetime.fromisoformat(iso_time.replace("Z", "+00:00"))
        delta = reset - datetime.now().astimezone()
        hours = int(delta.total_seconds() // 3600)
        minutes = int((delta.total_seconds() % 3600) // 60)
        # A weekly window is two days out more often than not, and nobody reads
        # "167h 28m" as "a week".
        if hours >= 48:
            return f"{hours // 24}d {hours % 24}h"
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes}m"
    except Exception:
        return "?"


def format_reset_epoch(epoch: int | None, unit: float = 1.0) -> str:
    """format_reset_time for APIs that answer in epoch seconds or milliseconds."""
    if not epoch:
        return "?"
    try:
        when = datetime.fromtimestamp(epoch / unit, tz=timezone.utc)
        return format_reset_time(when.isoformat())
    except Exception:
        return "?"


def window_label(minutes: int | None) -> str:
    """Name a rate-limit window by its length.

    Only the windows these plans actually use are named; anything else keeps its
    raw number, because mislabelling a monthly cap as weekly is worse than not
    labelling it.
    """
    return {300: "5h", 10080: "1w", 43200: "30d"}.get(minutes) or (
        f"{minutes}m" if minutes else "window"
    )


# --- Claude ---

def get_access_token() -> str | None:
    try:
        creds = json.loads(CREDENTIALS_FILE.read_text())
        return creds.get("claudeAiOauth", {}).get("accessToken")
    except Exception:
        return None


def detect_claude_code_version() -> str | None:
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
    lying, so the version is read from the installed package instead.
    """
    override = os.environ.get("CLAUDE_USAGE_USER_AGENT")
    if override:
        return override
    version = detect_claude_code_version()
    return f"claude-code/{version}" if version else None


def show_claude(provider: dict) -> dict:
    # Told apart on purpose: "never logged in" is a setup step the user can act
    # on, "fetch failed" is transient.
    token = get_access_token()
    if not token:
        return failed(provider, "not signed in",
                      f"no OAuth token in {CREDENTIALS_FILE}")

    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "anthropic-beta": "oauth-2025-04-20",
    }
    agent = claude_user_agent()
    if agent:
        headers["User-Agent"] = agent

    usage = curl_json(USAGE_API_URL, headers, {"Authorization": f"Bearer {token}"})
    if not usage:
        return failed(provider, "unable to fetch usage")

    windows = []
    for label, key in (("5h", "five_hour"), ("1w", "seven_day")):
        window = usage.get(key) or {}
        if window.get("utilization") is None:
            continue
        windows.append({
            "label": label,
            "pct": float(window["utilization"]),
            "reset": format_reset_time(window.get("resets_at")),
        })

    if not windows:
        return failed(provider, "usage response had no windows")

    lines = []
    for w in windows:
        line = f"{w['label']}: {w['pct']:.0f}%"
        if w["reset"] != "?":
            line += f" (resets in {w['reset']})"
        lines.append(line)

    sonnet = usage.get("seven_day_sonnet") or {}
    if sonnet.get("utilization") is not None:
        lines.append(f"Sonnet 1w: {float(sonnet['utilization']):.0f}%")

    # The window closest to its cap is the one that will stop you working, so
    # that is the one worth the headline — the same rule every other provider
    # here follows. Pinning this to the 5-hour window meant a bar reading "1%"
    # while the weekly allowance sat at 98%.
    headline = max(windows, key=lambda w: w["pct"])
    return result(provider, f"{headline['pct']:.0f}%", headline["pct"],
                  usage_class(headline["pct"]), lines)


# --- OpenRouter ---

def show_openrouter(provider: dict) -> dict:
    api_key = provider_key(provider) or (os.environ.get("OPENROUTER_API_KEY") or "").strip()
    if not api_key:
        return failed(provider, "no API key configured",
                      f"key file: {provider.get('apiKeyFile') or '<unset>'}")

    response = curl_json(OPENROUTER_API_URL, {"Accept": "application/json"},
                         {"Authorization": f"Bearer {api_key}"})
    if not response:
        return failed(provider, "unable to fetch balance")

    data = response.get("data", {})
    total = data.get("total_credits", 0)
    used = data.get("total_usage", 0)
    balance = total - used

    # A balance is the inverse of a utilisation: low is bad. Mapped onto the
    # same three classes so the bar's colours mean one thing across providers.
    level = "critical" if balance < 1 else "warning" if balance < 5 else "normal"
    return result(provider, f"${balance:.2f}", None, level,
                  [f"balance: ${balance:.2f}",
                   f"used: ${used:.2f} of ${total:.2f}"])


# --- Z.AI / GLM coding plan ---

# The quota endpoint reports each window as a (number, unit) pair. Only the two
# the coding plan actually uses are named.
ZAI_WINDOW_UNITS = {3: "h", 6: "w"}


def zai_window_label(limit: dict) -> str:
    suffix = ZAI_WINDOW_UNITS.get(limit.get("unit"))
    number = limit.get("number")
    if suffix and number:
        return f"{number}{suffix}"
    return f"unit {limit.get('unit')}×{number}"


def show_zai(provider: dict) -> dict:
    api_key = provider_key(provider)
    if not api_key:
        return failed(provider, "no API key configured",
                      f"key file: {provider.get('apiKeyFile') or '<unset>'}")

    response = curl_json(ZAI_QUOTA_API_URL, {"Accept": "application/json"},
                         {"Authorization": f"Bearer {api_key}"})
    limits = ((response or {}).get("data") or {}).get("limits") or []
    if not limits:
        return failed(provider, "unable to fetch quota")

    # `percentage` comes back from the API too, but the pair it is derived from
    # is right here — computing it means the tooltip and the headline can never
    # disagree.
    windows = []
    for limit in limits:
        total = limit.get("usage") or 0
        used = limit.get("currentValue") or 0
        windows.append({
            "label": zai_window_label(limit),
            "pct": (used / total * 100) if total else 0,
            "used": used,
            "total": total,
            "reset": format_reset_epoch(limit.get("nextResetTime"), 1000.0),
        })

    lines = []
    for w in windows:
        line = f"{w['label']}: {w['pct']:.0f}% ({w['used']:.0f}/{w['total']:.0f}"
        line += f", resets in {w['reset']})" if w["reset"] != "?" else ")"
        lines.append(line)

    level = ((response or {}).get("data") or {}).get("level")
    if level:
        lines.append(f"plan: {level}")

    headline = max(windows, key=lambda w: w["pct"])
    return result(provider, f"{headline['pct']:.0f}%", headline["pct"],
                  usage_class(headline["pct"]), lines)


# --- Codex ---

def codex_rollouts() -> list[Path]:
    """Newest rollout transcripts first."""
    try:
        files = list(CODEX_SESSIONS_DIR.rglob("rollout-*.jsonl"))
    except Exception:
        return []
    return sorted(files, key=lambda p: p.stat().st_mtime, reverse=True)[:CODEX_ROLLOUT_SCAN]


def codex_last_rate_limits() -> dict | None:
    """The most recent rate-limit record Codex wrote to disk.

    Codex has no endpoint to ask "what is left"; the numbers arrive as a
    `rate_limits` field on the `token_count` event of every turn and are
    recorded in the session transcript. Reading the newest one back is what the
    CLI itself shows as "Rate Limits Remaining", and it costs no API call —
    which matters for something the bar refreshes on a timer.
    """
    for path in codex_rollouts():
        try:
            with path.open("rb") as fh:
                fh.seek(0, os.SEEK_END)
                fh.seek(max(0, fh.tell() - CODEX_TAIL_BYTES))
                # A mid-line seek yields one broken first line; json.loads
                # rejects it and the loop moves on.
                tail = fh.read().decode("utf-8", "replace").splitlines()
        except Exception:
            continue
        for line in reversed(tail):
            if '"rate_limits"' not in line:
                continue
            try:
                limits = json.loads(line).get("payload", {}).get("rate_limits")
            except Exception:
                continue
            if limits:
                return limits
    return None


def show_codex(provider: dict) -> dict:
    limits = codex_last_rate_limits()
    if not limits:
        return failed(provider, "no rate-limit record found",
                      f"looked in {CODEX_SESSIONS_DIR}",
                      "run a Codex turn once so it writes one")

    windows = []
    for slot in ("primary", "secondary"):
        window = limits.get(slot)
        if not window or window.get("used_percent") is None:
            continue
        windows.append({
            "label": window_label(window.get("window_minutes")),
            "pct": float(window["used_percent"]),
            "reset": format_reset_epoch(window.get("resets_at")),
        })

    if not windows:
        return failed(provider, "rate-limit record has no windows")

    lines = []
    for w in windows:
        line = f"{w['label']}: {w['pct']:.0f}%"
        if w["reset"] != "?":
            line += f" (resets in {w['reset']})"
        lines.append(line)

    credits = limits.get("credits") or {}
    if credits.get("unlimited"):
        lines.append("credits: unlimited")
    elif credits.get("balance") is not None:
        lines.append(f"credits: {credits['balance']}")
    if limits.get("plan_type"):
        lines.append(f"plan: {limits['plan_type']}")

    headline = max(windows, key=lambda w: w["pct"])
    return result(provider, f"{headline['pct']:.0f}%", headline["pct"],
                  usage_class(headline["pct"]), lines)


# --- Antigravity ---

def listening_ports(comm: str) -> list[int]:
    """Loopback TCP ports listened on by processes named `comm`.

    Antigravity picks its port at startup and writes it nowhere, so it has to be
    found: collect the socket inodes the process holds open, then look them up
    among the listening sockets in /proc/net/tcp. Pure /proc — no lsof or ss to
    depend on.
    """
    inodes = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if (proc / "comm").read_text().strip() != comm:
                continue
            for fd in (proc / "fd").iterdir():
                match = re.fullmatch(r"socket:\[(\d+)\]", os.readlink(fd))
                if match:
                    inodes.add(match.group(1))
        except Exception:
            continue
    if not inodes:
        return []

    ports = []
    try:
        for line in Path("/proc/net/tcp").read_text().splitlines()[1:]:
            fields = line.split()
            # 0A is TCP_LISTEN; local_address is hex "IP:PORT", little-endian IP.
            if len(fields) < 10 or fields[3] != "0A" or fields[9] not in inodes:
                continue
            ports.append(int(fields[1].split(":")[1], 16))
    except Exception:
        return []
    return sorted(set(ports))


def show_antigravity(provider: dict) -> dict:
    ports = listening_ports(provider.get("process") or "antigravity")
    if not ports:
        return failed(provider, "not running",
                      "start Antigravity — its quota comes from the",
                      "language server it runs on localhost")

    # Several Antigravity processes each open several ports and only some
    # answer this RPC, so every candidate is tried before giving up. Self-signed
    # loopback certificate, hence the insecure flag.
    response = None
    for port in ports:
        response = curl_json(
            f"https://127.0.0.1:{port}{ANTIGRAVITY_RPC_PATH}",
            {"Content-Type": "application/json"}, data="{}", insecure=True,
        )
        if response and (response.get("response") or {}).get("groups"):
            break
        response = None

    if not response:
        return failed(provider, "language server did not answer",
                      f"tried ports: {', '.join(map(str, ports))}")

    buckets = []
    for group in (response.get("response") or {}).get("groups") or []:
        for bucket in group.get("buckets") or []:
            fraction = bucket.get("remainingFraction")
            if fraction is None:
                continue
            # The API reports what is LEFT; everything else on this bar reports
            # what is USED, and a row that silently means the opposite of the
            # one above it is worse than no row.
            buckets.append({
                "label": f"{group.get('displayName', '?')} {bucket.get('window', '?')}",
                "pct": (1.0 - float(fraction)) * 100.0,
                "reset": format_reset_time(bucket.get("resetTime")),
            })

    if not buckets:
        return failed(provider, "quota summary had no buckets")

    lines = []
    for b in buckets:
        line = f"{b['label']}: {b['pct']:.0f}%"
        if b["reset"] != "?":
            line += f" (resets in {b['reset']})"
        lines.append(line)

    headline = max(buckets, key=lambda b: b["pct"])
    return result(provider, f"{headline['pct']:.0f}%", headline["pct"],
                  usage_class(headline["pct"]), lines)


# --- rendering ---

BACKENDS = {
    "claude-oauth": show_claude,
    "openrouter": show_openrouter,
    "zai": show_zai,
    "codex": show_codex,
    "antigravity": show_antigravity,
}

LEVEL_RANK = {"normal": 0, "warning": 1, "critical": 2, "error": 3}


def report(provider: dict) -> dict:
    backend = BACKENDS.get(provider.get("backend"))
    if backend is None:
        return failed(provider, f"unknown backend '{provider.get('backend')}'")
    try:
        return backend(provider)
    except Exception as exc:
        # One provider's bug must not blank the whole bar.
        return failed(provider, f"reporter failed: {exc}")


def main():
    providers = load_providers()
    with ThreadPoolExecutor(max_workers=max(1, len(providers))) as pool:
        results = list(pool.map(report, providers))

    # Deliberately uncoloured. The bar's colours belong to the layout, not to
    # runtime status — the same reason the agent chip keeps one background and
    # carries state in its dots instead.
    text = "  ".join(f"{r['label']} {r['body']}" for r in results)

    blocks = []
    for r in results:
        head = f"{r['label']} · {r['name']}"
        blocks.append("\n".join([head] + [f"  {line}" for line in r["lines"]]))

    worst = max((r["level"] for r in results), key=lambda l: LEVEL_RANK.get(l, 0),
                default="normal")

    print(json.dumps({
        "text": text,
        "tooltip": "\n\n".join(blocks),
        # An unreachable provider is not a reason to paint the chip red: the
        # other four are still telling the truth. Errors show as "?" in place.
        "class": worst if worst != "error" else "normal",
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
