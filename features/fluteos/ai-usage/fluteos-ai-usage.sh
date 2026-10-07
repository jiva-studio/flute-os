#!/usr/bin/env bash
# Waybar module: Claude/OpenRouter token usage AND live agent statuses, merged
# into one chip.
#
# Two things that are both "how is Claude doing right now" used to occupy two
# separate slots on the bar. Here the usage percentage stays the primary text
# and the agent counters are appended to it; both tooltips are stacked.
#
# The two halves refresh at very different rates. Agent statuses come from a
# local registry and need a ~2s poll to feel live; usage is a network call to
# the Anthropic/OpenRouter API and must not run at that rate. So the usage half
# is cached on disk with a TTL and only refetched when stale.
#
# Dependencies (via environment):
#   CLAUDE_USAGE_BIN  - the python usage reporter (required)
#   JQ                - jq (required)
#   MODE_FILE         - which backend the usage half reports on
#   OPENROUTER_API_KEY_FILE
#                     - path (not contents) of the OpenRouter key file, read by
#                       the reporter at runtime; empty/unset → OpenRouter mode
#                       reports "no API key configured"
#   CACHE_DIR         - where the usage response is cached
#   USAGE_TTL         - seconds before the usage half is refetched
#   AGENTS_WIDGET     - agent status widget, resolved from PATH; optional, the
#                       module degrades to plain usage when the agents feature
#                       is off

set -u

JQ="${JQ:-jq}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/fluteos/claude-usage}"
USAGE_TTL="${USAGE_TTL:-300}"
MODE_FILE="${MODE_FILE:-$HOME/.cache/ai-usage/mode}"

mkdir -p "$CACHE_DIR"

# Cache per mode, so flipping claude <-> openrouter shows the new backend
# immediately instead of serving the other one's cached number.
MODE=$(cat "$MODE_FILE" 2>/dev/null || echo claude)
case "$MODE" in
  openrouter) ;;
  *) MODE=claude ;;
esac
CACHE="$CACHE_DIR/usage-$MODE.json"

usage_is_fresh() {
  [ -s "$CACHE" ] || return 1
  local age now mtime
  now=$(date +%s)
  mtime=$(stat -c %Y "$CACHE" 2>/dev/null) || return 1
  age=$((now - mtime))
  [ "$age" -lt "$USAGE_TTL" ]
}

if ! usage_is_fresh; then
  FRESH=$("$CLAUDE_USAGE_BIN" "$@" 2>/dev/null)
  # Only overwrite the cache with something that parses — a failed fetch should
  # keep showing the last known number rather than blanking the module.
  #
  # And only with a SUCCESS payload. "not signed in" and "no API key configured"
  # are well-formed JSON with exit 0, so they passed the parse gate and were
  # cached for the full TTL: signing in or dropping the key file in place left
  # the chip showing `?` for another five minutes with no way to hurry it.
  if [ -n "$FRESH" ] \
     && "$JQ" -e . >/dev/null 2>&1 <<<"$FRESH" \
     && [ "$("$JQ" -r '.class // ""' <<<"$FRESH")" != "error" ]; then
    printf '%s' "$FRESH" >"$CACHE"
  fi
fi

USAGE=$(cat "$CACHE" 2>/dev/null)
# With no cached number to fall back on, a fresh error payload is still the best
# thing to show: its tooltip names the actual problem ("not signed in", "no API
# key configured") where the generic fallback below only says "failed".
if [ -z "$USAGE" ] && [ -n "${FRESH:-}" ] && "$JQ" -e . >/dev/null 2>&1 <<<"$FRESH"; then
  USAGE="$FRESH"
fi
if [ -z "$USAGE" ]; then
  USAGE='{"text":"<span size='"'"'16pt'"'"' rise='"'"'-2pt'"'"'>󰚩</span> ?","tooltip":"Failed to fetch limits","class":"error"}'
fi

# Agent half. Absent binary, non-zero exit or garbage output all collapse to
# "no agents" — the usage half must still render.
AGENTS=""
AGENTS_WIDGET="${AGENTS_WIDGET:-fluteos-agents-widget}"
if command -v "$AGENTS_WIDGET" >/dev/null 2>&1; then
  AGENTS=$("$AGENTS_WIDGET" 2>/dev/null)
fi
if [ -z "$AGENTS" ] || ! "$JQ" -e . >/dev/null 2>&1 <<<"$AGENTS"; then
  AGENTS='{"compact":"","tooltip":"","class":"empty"}'
fi

"$JQ" -nc --argjson u "$USAGE" --argjson a "$AGENTS" '
  ($a.compact // "")        as $counts
  | ($a.class // "empty")   as $astate

  | {
      # Usage percentage stays the headline; agent counters trail it.
      text: (($u.text // "")
             + (if $counts == "" then "" else "  " + $counts end)),

      # "Агентов нет" is not worth a paragraph of tooltip when the usual state
      # is no agents running.
      tooltip: ([ ($u.tooltip // ""),
                  (if $astate == "empty" then "" else ($a.tooltip // "") end) ]
                | map(select(. != "")) | join("\n\n")),

      # Both halves colour the chip: the usage class keeps its warning levels,
      # the agents class is prefixed so CSS can let "waiting" break out to red.
      class: [ ($u.class // "normal"), "agents-" + $astate ]
    }'
