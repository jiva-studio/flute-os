#!/usr/bin/env bash
# Open a wezterm in the cwd of the current niri workspace.
# If current workspace is not in registry (or has no name), fall back to $HOME.
#
# Dependencies: JQ, NIRI, WEZTERM, REGISTRY (set via environment)

WS_NAME=$("$NIRI" msg --json workspaces 2>/dev/null \
  | "$JQ" -r '.[] | select(.is_focused) | .name // empty')

if [ -n "$WS_NAME" ]; then
  CWD=$("$JQ" -r --arg id "$WS_NAME" '.[$id].cwd // empty' "$REGISTRY" 2>/dev/null)
  if [ -n "$CWD" ] && [ -d "$CWD" ]; then
    exec "$WEZTERM" start --always-new-process --cwd "$CWD"
  fi
fi

exec "$WEZTERM" start --always-new-process
