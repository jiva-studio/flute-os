#!/usr/bin/env bash
# Launch Firefox with the workspace's browser profile, placing the URL
# in the focused niri workspace — never in another one.
#
# Profile resolution:
#   1. $WORKSPACE_BROWSER_PROFILE (set by direnv when called from a workspace
#      terminal; or by fluteos-docs-open via direct invocation).
#   2. Focused niri workspace name → registry lookup. This is the authoritative
#      fallback because xdg-open on Wayland routes via xdg-desktop-portal which
#      spawns mime handlers over DBus — env vars do NOT propagate, so terminal-
#      clicked links would otherwise always fall back to DEFAULT_PROFILE.
#   3. $DEFAULT_PROFILE.
#
# Window selection:
#   - If the focused niri workspace already contains a firefox window, focus
#     it and let firefox's IPC deliver the URL there as a tab. (The focus +
#     short sleep is needed because firefox picks the target by its internal
#     last-active-window timestamp — without it, the URL races to whichever
#     window firefox had focused last, possibly on a different niri ws.)
#   - Otherwise spawn with --new-window so the new window appears on the
#     currently focused niri workspace.
#
# Dependencies: FIREFOX, DEFAULT_PROFILE, JQ, NIRI, REGISTRY (env).

PROFILE="${WORKSPACE_BROWSER_PROFILE:-}"

if [ -z "$PROFILE" ] && [ -n "${NIRI:-}" ] && [ -n "${JQ:-}" ] && [ -n "${REGISTRY:-}" ] && [ -f "$REGISTRY" ]; then
  WS=$("$NIRI" msg --json workspaces 2>/dev/null \
    | "$JQ" -r '.[] | select(.is_focused) | .name // empty')
  if [ -n "$WS" ]; then
    PROFILE=$("$JQ" -r --arg id "$WS" '.[$id].browserProfile // empty' "$REGISTRY")
  fi
fi

PROFILE="${PROFILE:-$DEFAULT_PROFILE}"

WIN_ID=""
if [ -n "${NIRI:-}" ] && [ -n "${JQ:-}" ]; then
  FOCUSED_WS_ID=$("$NIRI" msg --json workspaces 2>/dev/null \
    | "$JQ" -r '.[] | select(.is_focused) | .id // empty')
  if [ -n "$FOCUSED_WS_ID" ]; then
    WIN_ID=$("$NIRI" msg --json windows 2>/dev/null \
      | "$JQ" -r --argjson ws "$FOCUSED_WS_ID" '
          .[] | select(.workspace_id == $ws
            and ((.app_id // "") | ascii_downcase | test("firefox"))) | .id' \
      | head -n1)
  fi
fi

if [ -n "$WIN_ID" ]; then
  "$NIRI" msg action focus-window --id "$WIN_ID" >/dev/null 2>&1 || true
  sleep 0.05
  exec "$FIREFOX" -P "$PROFILE" "$@"
fi

exec "$FIREFOX" -P "$PROFILE" --new-window "$@"
