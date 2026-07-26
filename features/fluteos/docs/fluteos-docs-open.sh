#!/usr/bin/env bash
# fluteos-docs-open [project-id-or-dir] [page]
#
# Opens a doc page in browser routed through fluteos-workspace-browser.
# Page format: "auth/sessions" | "auth/sessions.md" | "auth/sessions#token-rotation" | "" (root)
#
# Browser profile is taken from the project's group (registry.<id>.browserProfile)
# and exported as $WORKSPACE_BROWSER_PROFILE so xdg-open's mime handler picks it up
# regardless of the calling context (terminal, which-key daemon, agent).

set -uo pipefail

# shellcheck source=./_resolve-workspace.sh
source "$RESOLVE_HELPER"

ARG1="${1:-}"
ARG2="${2:-}"

# Disambiguate: ARG1 is project if it looks like an id ("<g>:<p>") or absolute dir.
# Otherwise ARG1 is the page (and project comes from current workspace context).
RESOLVE_ARG=""
PAGE=""
if [[ "$ARG1" == *:* ]] || [ -d "$ARG1" ]; then
  RESOLVE_ARG="$ARG1"
  PAGE="$ARG2"
else
  PAGE="$ARG1"
fi

if ! resolve_workspace "$RESOLVE_ARG"; then
  echo "fluteos-docs-open: cannot resolve workspace (no arg, no \$WORKSPACE_*, no focused niri workspace)" >&2
  exit 2
fi

# Ensure server is running, grab URL
SERVE_OUT="$(fluteos-docs-serve "$PROJECT_ID")" || {
  echo "fluteos-docs-open: failed to start server" >&2
  exit 3
}
URL="${SERVE_OUT#URL=}"

# Translate page → docsify URL fragment
ANCHOR=""
if [[ "$PAGE" == *"#"* ]]; then
  ANCHOR="${PAGE##*#}"
  PAGE="${PAGE%%#*}"
fi
PAGE="${PAGE%.md}"

if [ -z "$PAGE" ] || [ "$PAGE" = "/" ]; then
  TARGET="$URL/"
else
  PAGE="${PAGE#/}"
  if [ -n "$ANCHOR" ]; then
    TARGET="$URL/#/$PAGE?id=$ANCHOR"
  else
    TARGET="$URL/#/$PAGE"
  fi
fi

# Call the workspace-aware browser script directly instead of going through
# xdg-open. xdg-open on Wayland routes via xdg-desktop-portal which spawns the
# mime handler over DBus — env vars (incl. WORKSPACE_BROWSER_PROFILE) do NOT
# propagate, so the profile silently fell back to DEFAULT_PROFILE and docs
# opened in the wrong firefox instance ("a fresh window with bare profile").
[ -n "$BROWSER_PROFILE" ] && export WORKSPACE_BROWSER_PROFILE="$BROWSER_PROFILE"
setsid fluteos-workspace-browser "$TARGET" >/dev/null 2>&1 < /dev/null &
disown
echo "$TARGET"
