#!/usr/bin/env bash
# fluteos-docs-check
#
# Returns 0 if the focused niri workspace is in the registry AND its project
# has a docs/ folder. Used as enabledCmd for the docs menu.
#
# Cannot rely on $WORKSPACE_CWD — which-key daemon inherits env from
# niri-session.target, not from any specific workspace.
#
# Dependencies: JQ, NIRI, REGISTRY (set via environment by the wrapper).

set -uo pipefail

WS=$("$NIRI" msg --json workspaces 2>/dev/null \
  | "$JQ" -r '.[] | select(.is_focused) | .name // empty')

[ -z "$WS" ] && exit 1

CWD=$("$JQ" -r --arg id "$WS" '.[$id].cwd // empty' "$REGISTRY")
[ -z "$CWD" ] && exit 1

[ -d "$CWD/docs" ]
