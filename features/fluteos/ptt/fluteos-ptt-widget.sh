#!/usr/bin/env bash
# PTT Widget script - outputs JSON for waybar
# Dependencies: JQ, STDBUF, FLUTEOS_PTT_CONFIG (set via environment)
set -uo pipefail

MODE_FILE="$HOME/.cache/ptt/mode"
CONNECTION_FILE="$HOME/.cache/ptt/connection"

# Emit a visible error state and exit non-zero. A widget that silently printed a
# plausible-looking default would hide a broken installation behind a label that
# happens to read fine.
fail() {
  "$STDBUF" -oL echo "{\"text\": \"󰍬 !\", \"tooltip\": \"fluteos-ptt: $1\", \"class\": \"error\"}"
  echo "fluteos-ptt-widget: $1" >&2
  exit 1
}

# The generated config is the ONLY source of mode names. No `// "RAW"` fallback:
# that fallback was one of three copies of the mode table, and the copies had
# already drifted from each other.
if [ -z "${FLUTEOS_PTT_CONFIG:-}" ]; then
  fail "FLUTEOS_PTT_CONFIG is not set"
fi
if [ ! -r "$FLUTEOS_PTT_CONFIG" ]; then
  fail "cannot read config at $FLUTEOS_PTT_CONFIG"
fi

# Read current mode; an unknown/absent one resolves to the CONFIGURED default
# (e.g. after a mode was renamed), never to a hardcoded name.
CURRENT_MODE=$(cat "$MODE_FILE" 2>/dev/null || true)
if [ -z "$CURRENT_MODE" ] || ! "$JQ" -e --arg m "$CURRENT_MODE" '.modes | has($m)' "$FLUTEOS_PTT_CONFIG" >/dev/null; then
  CURRENT_MODE=$("$JQ" -er '.defaultMode' "$FLUTEOS_PTT_CONFIG") || fail "config has no defaultMode"
fi

MODE_NAME=$("$JQ" -er --arg m "$CURRENT_MODE" '.modes[$m].name' "$FLUTEOS_PTT_CONFIG") ||
  fail "mode '$CURRENT_MODE' has no name in $FLUTEOS_PTT_CONFIG"

# Read connection state
if [ -f "$CONNECTION_FILE" ]; then
  CONNECTION_STATE=$(cat "$CONNECTION_FILE")
else
  CONNECTION_STATE="disconnected"
fi

# Connection status icon (4 states) - diamonds
case "$CONNECTION_STATE" in
  streaming)
    CONN_ICON="●"
    ;;
  connected)
    CONN_ICON="◆"
    ;;
  connecting)
    CONN_ICON="◈"
    ;;
  *)
    CONN_ICON="◇"
    ;;
esac

# Output JSON for waybar (stdbuf for unbuffered output)
"$STDBUF" -oL echo "{\"text\": \"$CONN_ICON $MODE_NAME\", \"tooltip\": \"PTT: $MODE_NAME\\nConnection: $CONNECTION_STATE\", \"class\": \"$CURRENT_MODE\"}"
