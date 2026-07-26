#!/usr/bin/env bash
# Source-able helper to resolve workspace context for docs scripts.
# Sets: PROJECT_ID, PROJECT_DIR, DOCS_DIR, BROWSER_PROFILE, DOCS_PORT
#
# Resolution chain (in order):
#   1. Explicit arg ($1) — workspace id "<group>:<project>" or absolute project dir
#   2. $WORKSPACE_CWD env (set by direnv when invoked from a workspace terminal)
#   3. Currently focused niri workspace name (when invoked from which-key daemon)
#
# Dependencies in env: JQ, NIRI, REGISTRY

resolve_workspace() {
  local arg="${1:-}"

  PROJECT_ID=""
  PROJECT_DIR=""
  DOCS_DIR=""
  BROWSER_PROFILE=""
  DOCS_PORT=""

  # 1. Explicit arg
  if [ -n "$arg" ]; then
    if [ -d "$arg" ]; then
      PROJECT_DIR="$arg"
      PROJECT_ID="$(basename "$(dirname "$arg")"):$(basename "$arg")"
    elif [[ "$arg" == *:* ]]; then
      PROJECT_ID="$arg"
    fi
  fi

  # 2. Inherit from direnv-loaded environment
  if [ -z "$PROJECT_ID" ] && [ -n "${WORKSPACE_ID:-}" ]; then
    PROJECT_ID="$WORKSPACE_ID"
  fi
  if [ -z "$PROJECT_DIR" ] && [ -n "${WORKSPACE_CWD:-}" ]; then
    PROJECT_DIR="$WORKSPACE_CWD"
    [ -z "$PROJECT_ID" ] && PROJECT_ID="$(basename "$(dirname "$PROJECT_DIR")"):$(basename "$PROJECT_DIR")"
  fi

  # 3. Niri focused workspace (which-key daemon context)
  if [ -z "$PROJECT_ID" ] && [ -n "${NIRI:-}" ]; then
    PROJECT_ID=$("$NIRI" msg --json workspaces 2>/dev/null \
      | "$JQ" -r '.[] | select(.is_focused) | .name // empty')
  fi

  if [ -z "$PROJECT_ID" ]; then
    return 1
  fi

  # Look up project paths and profile in the registry
  if [ -n "${REGISTRY:-}" ] && [ -f "$REGISTRY" ]; then
    local entry cwd docs browser
    entry=$("$JQ" --arg id "$PROJECT_ID" '.[$id] // empty' "$REGISTRY")
    if [ -n "$entry" ] && [ "$entry" != "null" ]; then
      # `jq -r '.x // empty'` prints empty string for both missing and JSON null,
      # so we don't have to filter the literal "null" downstream.
      cwd=$(echo "$entry" | "$JQ" -r '.cwd // empty')
      docs=$(echo "$entry" | "$JQ" -r '.docsDir // empty')
      browser=$(echo "$entry" | "$JQ" -r '.browserProfile // empty')
      docs_port=$(echo "$entry" | "$JQ" -r '.docsPort // empty')
      [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$cwd"
      DOCS_DIR="$docs"
      BROWSER_PROFILE="$browser"
      DOCS_PORT="$docs_port"
    fi
  fi

  [ -z "$DOCS_DIR" ] && [ -n "$PROJECT_DIR" ] && DOCS_DIR="$PROJECT_DIR/docs"

  if [ -z "$PROJECT_ID" ] || [ -z "$PROJECT_DIR" ]; then
    return 1
  fi
  if [ ! -d "$PROJECT_DIR" ]; then
    echo "resolve_workspace: project dir '$PROJECT_DIR' (id '$PROJECT_ID') does not exist" >&2
    return 1
  fi
  return 0
}
