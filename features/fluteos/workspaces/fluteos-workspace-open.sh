#!/usr/bin/env bash
# Open a workspace by id. Sets niri workspace name, exports WORKSPACE_* env,
# launches sessionApps if configured, otherwise opens a single terminal in cwd.
#
# Usage: fluteos-workspace-open <id>
# Where <id> is "<group>" or "<group>:<project>" (e.g. "acme", "acme:widgets")
#
# Dependencies: JQ, NIRI, WEZTERM, NOTIFY_SEND, REGISTRY (set via environment)

set -uo pipefail

# Tracing is opt-in. It used to be unconditional, which meant every workspace
# open rewrote the log with a full command trace AND swallowed all output —
# including the critical notify-send failures below, which the caller could then
# never see. Set FLUTEOS_WORKSPACE_DEBUG=1 to get the old behaviour back.
if [ -n "${FLUTEOS_WORKSPACE_DEBUG:-}" ]; then
  LOG_FILE="${FLUTEOS_LOG_DIR:-${XDG_RUNTIME_DIR:-/tmp}}/fluteos-workspace-open.log"
  exec > "$LOG_FILE" 2>&1
  set -x
fi

ID="${1:-}"

if [ -z "$ID" ]; then
  "$NOTIFY_SEND" -u critical "Workspace Open" "No workspace id provided"
  exit 1
fi

if ! "$JQ" -e --arg id "$ID" '.[$id]' "$REGISTRY" > /dev/null 2>&1; then
  "$NOTIFY_SEND" -u critical "Workspace Open" "Workspace '$ID' not found"
  exit 1
fi

WS=$("$JQ" --arg id "$ID" '.[$id]' "$REGISTRY")
GROUP=$(echo "$WS" | "$JQ" -r '.group')
PROJECT=$(echo "$WS" | "$JQ" -r '.project')
CWD=$(echo "$WS" | "$JQ" -r '.cwd')
SOURCE_DIR=$(echo "$WS" | "$JQ" -r '.sourceDir')
AGENT_DIR=$(echo "$WS" | "$JQ" -r '.agentDir')
DOCS_DIR=$(echo "$WS" | "$JQ" -r '.docsDir')
RESOURCES_DIR=$(echo "$WS" | "$JQ" -r '.resourcesDir')
DISPLAY_NAME=$(echo "$WS" | "$JQ" -r '.displayName')
BROWSER_PROFILE=$(echo "$WS" | "$JQ" -r '.browserProfile')

# Export workspace identity for any process spawned from here.
# These must be set BEFORE sessionApps spawn so $WORKSPACE_SOURCE_DIR etc.
# expand correctly in their commands (direnv runs later, after spawn).
export WORKSPACE_ID="$ID"
export WORKSPACE_GROUP="$GROUP"
export WORKSPACE_PROJECT="$PROJECT"
export WORKSPACE_CWD="$CWD"
export WORKSPACE_SOURCE_DIR="$SOURCE_DIR"
export WORKSPACE_AGENT_DIR="$AGENT_DIR"
export WORKSPACE_DOCS_DIR="$DOCS_DIR"
export WORKSPACE_RESOURCES_DIR="$RESOURCES_DIR"
export WORKSPACE_BROWSER_PROFILE="$BROWSER_PROFILE"

# Rename current niri workspace
"$NIRI" msg action set-workspace-name "$ID"

# If no sessionApps configured, just open a terminal in cwd
NUM_APPS=$(echo "$WS" | "$JQ" '.sessionApps | length')
if [ "$NUM_APPS" -eq 0 ]; then
  "$WEZTERM" start --always-new-process --cwd "$CWD" &
  "$NOTIFY_SEND" "Workspace" "$DISPLAY_NAME"
  exit 0
fi

# --- sessionApps launch (mirrors niri/session-restore.sh) ---

TIMEOUT="${FLUTEOS_WORKSPACE_TIMEOUT:-10}"

get_windows() {
  "$NIRI" msg --json windows 2>/dev/null || echo "[]"
}

# id of the currently focused niri workspace; empty if niri is unreachable.
# Scoping is_running/get_window_id to this id avoids cross-workspace false
# positives for apps that share an app_id (e.g. firefox, which has no
# --class flag — every window is `app_id="firefox"` regardless of project).
focused_ws_id() {
  "$NIRI" msg --json workspaces 2>/dev/null \
    | "$JQ" -r '.[] | select(.is_focused) | .id // empty'
}

is_running() {
  local app_id="$1" ws
  ws=$(focused_ws_id)
  [ -n "$ws" ] || return 1
  get_windows | "$JQ" -e --arg id "$app_id" --argjson ws "$ws" \
    '.[] | select(.app_id == $id and .workspace_id == $ws)' > /dev/null 2>&1
}

get_window_id() {
  local app_id="$1" ws
  ws=$(focused_ws_id)
  [ -n "$ws" ] || return 1
  get_windows | "$JQ" -r --arg id "$app_id" --argjson ws "$ws" \
    '.[] | select(.app_id == $id and .workspace_id == $ws) | .id' | head -1
}

wait_for_window() {
  local app_id="$1"
  local start_time
  start_time=$(date +%s)
  while ! is_running "$app_id"; do
    local current_time elapsed
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      echo "Timeout waiting for $app_id"
      return 1
    fi
    sleep 0.2
  done
  return 0
}

COLUMNS=$(echo "$WS" | "$JQ" -c '[.sessionApps | group_by(.column)[] | {column: .[0].column, apps: .}] | sort_by(.column)')

while IFS= read -r col_data; do
  COLUMN_IDX=$(echo "$col_data" | "$JQ" -r '.column')
  COL_APPS=$(echo "$col_data" | "$JQ" -c '.apps')
  NUM_COL_APPS=$(echo "$COL_APPS" | "$JQ" 'length')

  echo "=== Column $COLUMN_IDX ($NUM_COL_APPS apps) ==="

  COLUMN_WIDTH=""
  FIRST_WINDOW_ID=""

  for i in $(seq 0 $((NUM_COL_APPS - 1))); do
    APP=$(echo "$COL_APPS" | "$JQ" -c ".[$i]")
    APP_ID=$(echo "$APP" | "$JQ" -r '.appId')
    APP_NAME=$(echo "$APP" | "$JQ" -r '.name')
    WIDTH=$(echo "$APP" | "$JQ" -r '.width // empty')

    if [ -z "$FIRST_WINDOW_ID" ] && [ -n "$WIDTH" ]; then
      COLUMN_WIDTH="$WIDTH"
    fi

    if is_running "$APP_ID"; then
      echo "  $APP_NAME already running"
      if [ -z "$FIRST_WINDOW_ID" ]; then
        FIRST_WINDOW_ID=$(get_window_id "$APP_ID")
      fi
      continue
    fi

    COMMAND=$(echo "$APP" | "$JQ" -r '.command | @sh')
    echo "  Launching $APP_NAME..."
    eval "$COMMAND" &

    if ! wait_for_window "$APP_ID"; then
      "$NOTIFY_SEND" -u warning "Workspace Open" "Timeout waiting for $APP_NAME"
      continue
    fi

    sleep 0.3

    WINDOW_ID=$(get_window_id "$APP_ID")
    if [ -z "$WINDOW_ID" ]; then
      echo "  Warning: could not get window ID for $APP_ID"
      continue
    fi

    TAG=$(echo "$APP" | "$JQ" -r '.tag // empty')
    if [ -n "$TAG" ]; then
      echo "  Assigning tag $TAG to $APP_NAME"
      "$NIRI" msg action focus-window --id "$WINDOW_ID"
      sleep 0.1
      niri-tags set "$TAG"
    fi

    if [ -z "$FIRST_WINDOW_ID" ]; then
      FIRST_WINDOW_ID="$WINDOW_ID"
      echo "  First window: $WINDOW_ID"
    else
      echo "  Focusing first window $FIRST_WINDOW_ID to consume $APP_NAME"
      "$NIRI" msg action focus-window --id "$FIRST_WINDOW_ID"
      sleep 0.1
      "$NIRI" msg action consume-window-into-column
      sleep 0.2
    fi
  done

  if [ -n "$COLUMN_WIDTH" ]; then
    echo "  Setting width: $COLUMN_WIDTH"
    "$NIRI" msg action set-column-width "$COLUMN_WIDTH"
  fi

done < <(echo "$COLUMNS" | "$JQ" -c '.[]')

FOCUS_APP=$(echo "$WS" | "$JQ" -r '.sessionApps[] | select(.focus == true) | .appId' | head -1)
if [ -n "$FOCUS_APP" ]; then
  FOCUS_WINDOW_ID=$(get_window_id "$FOCUS_APP")
  if [ -n "$FOCUS_WINDOW_ID" ]; then
    "$NIRI" msg action focus-window --id "$FOCUS_WINDOW_ID"
  fi
fi

"$NOTIFY_SEND" "Workspace" "$DISPLAY_NAME: opened"
