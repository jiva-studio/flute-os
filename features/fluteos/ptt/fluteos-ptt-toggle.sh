#!/usr/bin/env bash
# PTT Toggle script - cycles through modes
# Dependencies: JQ, NOTIFY_SEND, PKILL, FLUTEOS_PTT_CONFIG (set via environment)
set -uo pipefail

MODE_FILE="$HOME/.cache/ptt/mode"

fail() {
  echo "fluteos-ptt-toggle: $1" >&2
  "$NOTIFY_SEND" -h string:x-canonical-private-synchronous:ptt-mode "PTT Mode" "error: $1" || true
  exit 1
}

# The generated config is the ONLY source of the mode table — no `// "RAW"`
# fallback. A fallback here would silently invent a mode set that no longer
# matches the one the daemon and the widget are using.
if [ -z "${FLUTEOS_PTT_CONFIG:-}" ]; then
  fail "FLUTEOS_PTT_CONFIG is not set"
fi
if [ ! -r "$FLUTEOS_PTT_CONFIG" ]; then
  fail "cannot read config at $FLUTEOS_PTT_CONFIG"
fi

# Ensure cache directory exists
mkdir -p "$(dirname "$MODE_FILE")"

# Read current mode; unknown/absent resolves to the CONFIGURED default.
CURRENT_MODE=$(cat "$MODE_FILE" 2>/dev/null || true)
if [ -z "$CURRENT_MODE" ] || ! "$JQ" -e --arg m "$CURRENT_MODE" '.modes | has($m)' "$FLUTEOS_PTT_CONFIG" >/dev/null; then
  CURRENT_MODE=$("$JQ" -er '.defaultMode' "$FLUTEOS_PTT_CONFIG") || fail "config has no defaultMode"
fi

# Get mode order from config
mapfile -t MODE_ORDER < <("$JQ" -er '.order[]' "$FLUTEOS_PTT_CONFIG") ||
  fail "config has no cycle order"
[ "${#MODE_ORDER[@]}" -gt 0 ] || fail "cycle order is empty"

# Find current mode index and get next
NEXT_MODE="${MODE_ORDER[0]}"
for i in "${!MODE_ORDER[@]}"; do
  if [ "${MODE_ORDER[$i]}" = "$CURRENT_MODE" ]; then
    NEXT_INDEX=$(( (i + 1) % ${#MODE_ORDER[@]} ))
    NEXT_MODE="${MODE_ORDER[$NEXT_INDEX]}"
    break
  fi
done

# Names come from the config or not at all.
MODE_NAME=$("$JQ" -er --arg m "$NEXT_MODE" '.modes[$m].name' "$FLUTEOS_PTT_CONFIG") ||
  fail "mode '$NEXT_MODE' has no name in $FLUTEOS_PTT_CONFIG"
MODE_ICON=$("$JQ" -r --arg m "$NEXT_MODE" '.modes[$m].icon // ""' "$FLUTEOS_PTT_CONFIG")

# Write new mode
echo "$NEXT_MODE" > "$MODE_FILE"

# Show notification
"$NOTIFY_SEND" -h string:x-canonical-private-synchronous:ptt-mode "PTT Mode" "$MODE_ICON $MODE_NAME"

# Signal waybar to update
"$PKILL" -SIGRTMIN+11 waybar || true
