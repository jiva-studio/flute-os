#!/usr/bin/env bash
# Waybar module: what is left on every AI plan, plus live agent statuses, merged
# into one chip.
#
# Two things that are both "how are my agents doing right now" used to occupy
# two separate slots on the bar. Here the per-provider quotas stay the primary
# text and the agent counters are appended to it; both tooltips are stacked.
#
# The two halves refresh at very different rates. Agent statuses come from a
# local registry and need a ~1s poll to feel live; quotas are network calls and
# must not run at that rate. So the quota half is cached on disk with a TTL and
# only refetched when stale. The reporter fetches all providers in parallel, so
# a refetch costs one round trip, not one per provider.
#
# Dependencies (via environment):
#   AI_USAGE_BIN    - the python reporter (required)
#   JQ              - jq (required)
#   PROVIDERS_FILE  - the provider catalogue, written from
#                     features.fluteos.ai-usage.providers. Each entry carries
#                     the PATH of its key file, never the key, which the
#                     reporter reads at runtime
#   CACHE_DIR       - where the quota response is cached
#   USAGE_TTL       - seconds before the quota half is refetched
#   AGENTS_WIDGET   - agent status widget, resolved from PATH; optional, the
#                     module degrades to plain quotas when the agents feature
#                     is off

set -u

JQ="${JQ:-jq}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/fluteos/ai-usage}"
USAGE_TTL="${USAGE_TTL:-300}"

mkdir -p "$CACHE_DIR"

# One cache for the lot. Every provider is on the bar at once now, so there is
# no selected provider to key the cache by — the reporter answers for all of
# them in a single run.
CACHE="$CACHE_DIR/usage.json"

usage_is_fresh() {
  [ -s "$CACHE" ] || return 1
  local now mtime
  now=$(date +%s)
  mtime=$(stat -c %Y "$CACHE" 2>/dev/null) || return 1
  [ "$((now - mtime))" -lt "$USAGE_TTL" ]
}

if ! usage_is_fresh; then
  FRESH=$("$AI_USAGE_BIN" "$@" 2>/dev/null)
  # Only overwrite the cache with something that parses — a failed fetch should
  # keep showing the last known numbers rather than blanking the module.
  #
  # Unlike the single-provider version this replaced, a payload is NOT rejected
  # for reporting an error: with five providers in one response, one that is
  # signed out would otherwise throw away the four that answered.
  if [ -n "$FRESH" ] && "$JQ" -e . >/dev/null 2>&1 <<<"$FRESH"; then
    printf '%s' "$FRESH" >"$CACHE"
  fi
fi

USAGE=$(cat "$CACHE" 2>/dev/null)
if [ -z "$USAGE" ] && [ -n "${FRESH:-}" ] && "$JQ" -e . >/dev/null 2>&1 <<<"$FRESH"; then
  USAGE="$FRESH"
fi
if [ -z "$USAGE" ]; then
  USAGE='{"text":"?","tooltip":"Failed to fetch limits","class":"error"}'
fi

# Agent half. Absent binary, non-zero exit or garbage output all collapse to
# "no agents" — the quota half must still render.
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
      # Quotas stay the headline; agent counters trail them.
      text: (($u.text // "")
             + (if $counts == "" then "" else "  " + $counts end)),

      # "No agents" is not worth a paragraph of tooltip when the usual state is
      # no agents running.
      tooltip: ([ ($u.tooltip // ""),
                  (if $astate == "empty" then "" else ($a.tooltip // "") end) ]
                | map(select(. != "")) | join("\n\n")),

      # Both halves colour the chip: the quota class keeps its warning levels,
      # the agents class is prefixed so CSS can let "waiting" break out.
      class: [ ($u.class // "normal"), "agents-" + $astate ]
    }'
