#!/usr/bin/env bash
# Returns 0 if current niri workspace is registered (agent menu becomes available).
# Dependencies: JQ, NIRI, REGISTRY (set via environment)

WS=$("$NIRI" msg --json workspaces 2>/dev/null \
  | "$JQ" -r '.[] | select(.is_focused) | .name // empty')

[ -z "$WS" ] && exit 1
"$JQ" -e --arg id "$WS" '.[$id] // empty' "$REGISTRY" > /dev/null 2>&1
