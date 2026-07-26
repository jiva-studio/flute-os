#!/usr/bin/env bash
# Session restore script - launches apps with layout for sessions
# Dependencies: JQ, NIRI, NOTIFY_SEND (set via environment)
set -uo pipefail

# Tracing is opt-in. It used to be unconditional, and it truncated a fixed,
# predictable path in a world-writable directory with `>` — a symlink planted at
# /tmp/niri-session-restore.log would have been followed. The log also carried a
# full trace of every command in the session, session URLs included.
if [ -n "${FLUTEOS_SESSION_DEBUG:-}" ]; then
  exec > "${XDG_RUNTIME_DIR:-/tmp}/niri-session-restore.log" 2>&1
  set -x
fi

COMPANY="$1"
CONFIG_FILE="$CONFIG_FILE"
TIMEOUT=10

# Check if company exists in config
if ! "$JQ" -e ".[\"$COMPANY\"]" "$CONFIG_FILE" > /dev/null 2>&1; then
  "$NOTIFY_SEND" -u critical "Session Restore" "Company '$COMPANY' not found"
  exit 1
fi

# Rename workspace
"$NIRI" msg action set-workspace-name "$COMPANY"

# Get session config for this company
SESSION=$("$JQ" -r ".[\"$COMPANY\"]" "$CONFIG_FILE")
DISPLAY_NAME=$(echo "$SESSION" | "$JQ" -r '.displayName')

# Get current windows
get_windows() {
  "$NIRI" msg --json windows 2>/dev/null || echo "[]"
}

# id of the currently focused niri workspace; scoping the lookups below to
# this id prevents cross-workspace false positives for apps that share an
# app_id (e.g. firefox — all windows are app_id="firefox").
focused_ws_id() {
  "$NIRI" msg --json workspaces 2>/dev/null \
    | "$JQ" -r '.[] | select(.is_focused) | .id // empty'
}

# Check if app is already running in the focused workspace (by app_id)
is_running() {
  local app_id="$1" ws
  ws=$(focused_ws_id)
  [ -n "$ws" ] || return 1
  get_windows | "$JQ" -e --arg id "$app_id" --argjson ws "$ws" \
    '.[] | select(.app_id == $id and .workspace_id == $ws)' > /dev/null 2>&1
}

# Get window id by app_id, scoped to the focused workspace
get_window_id() {
  local app_id="$1" ws
  ws=$(focused_ws_id)
  [ -n "$ws" ] || return 1
  get_windows | "$JQ" -r --arg id "$app_id" --argjson ws "$ws" \
    '.[] | select(.app_id == $id and .workspace_id == $ws) | .id' | head -1
}

# Wait for a specific app window to appear
wait_for_window() {
  local app_id="$1"
  local start_time=$(date +%s)
  while ! is_running "$app_id"; do
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    if [ $elapsed -ge $TIMEOUT ]; then
      echo "Timeout waiting for $app_id"
      return 1
    fi
    sleep 0.2
  done
  return 0
}

# Group apps by column, sorted by column index
COLUMNS=$(echo "$SESSION" | "$JQ" -c '[.apps | group_by(.column)[] | {column: .[0].column, apps: .}] | sort_by(.column)')

# Process each column sequentially: launch → wait → stack → set width
while IFS= read -r col_data; do
  COLUMN_IDX=$(echo "$col_data" | "$JQ" -r '.column')
  COL_APPS=$(echo "$col_data" | "$JQ" -c '.apps')
  NUM_APPS=$(echo "$COL_APPS" | "$JQ" 'length')

  echo "=== Column $COLUMN_IDX ($NUM_APPS apps) ==="

  COLUMN_WIDTH=""
  FIRST_WINDOW_ID=""

  for i in $(seq 0 $((NUM_APPS - 1))); do
    APP=$(echo "$COL_APPS" | "$JQ" -c ".[$i]")
    APP_ID=$(echo "$APP" | "$JQ" -r '.appId')
    APP_NAME=$(echo "$APP" | "$JQ" -r '.name')
    WIDTH=$(echo "$APP" | "$JQ" -r '.width // empty')

    # Remember width from first app
    if [ -z "$FIRST_WINDOW_ID" ] && [ -n "$WIDTH" ]; then
      COLUMN_WIDTH="$WIDTH"
    fi

    # Check if already running
    if is_running "$APP_ID"; then
      echo "  $APP_NAME already running"
      if [ -z "$FIRST_WINDOW_ID" ]; then
        FIRST_WINDOW_ID=$(get_window_id "$APP_ID")
      fi
      continue
    fi

    # Launch app
    COMMAND=$(echo "$APP" | "$JQ" -r '.command | @sh')
    echo "  Launching $APP_NAME..."
    eval "$COMMAND" &

    # Wait for window
    if ! wait_for_window "$APP_ID"; then
      "$NOTIFY_SEND" -u warning "Session Restore" \
        "Timeout waiting for $APP_NAME"
      continue
    fi

    sleep 0.3

    # Get window ID
    WINDOW_ID=$(get_window_id "$APP_ID")
    if [ -z "$WINDOW_ID" ]; then
      echo "  Warning: could not get window ID for $APP_ID"
      continue
    fi

    # Assign tag if specified
    TAG=$(echo "$APP" | "$JQ" -r '.tag // empty')
    if [ -n "$TAG" ]; then
      echo "  Assigning tag $TAG to $APP_NAME"
      "$NIRI" msg action focus-window --id "$WINDOW_ID"
      sleep 0.1
      niri-tags set "$TAG"
    fi

    # First window - just remember ID
    if [ -z "$FIRST_WINDOW_ID" ]; then
      FIRST_WINDOW_ID="$WINDOW_ID"
      echo "  First window: $WINDOW_ID"
    else
      # Focus FIRST window of column, then consume (pulls window from right)
      echo "  Focusing first window $FIRST_WINDOW_ID to consume $APP_NAME"
      "$NIRI" msg action focus-window --id "$FIRST_WINDOW_ID"
      sleep 0.1
      "$NIRI" msg action consume-window-into-column
      sleep 0.2
    fi
  done

  # Set column width
  if [ -n "$COLUMN_WIDTH" ]; then
    echo "  Setting width: $COLUMN_WIDTH"
    "$NIRI" msg action set-column-width "$COLUMN_WIDTH"
  fi

done < <(echo "$COLUMNS" | "$JQ" -c '.[]')

# Focus the window marked with focus=true
FOCUS_APP=$(echo "$SESSION" | "$JQ" -r '.apps[] | select(.focus == true) | .appId' | head -1)
if [ -n "$FOCUS_APP" ]; then
  FOCUS_WINDOW_ID=$(get_window_id "$FOCUS_APP")
  if [ -n "$FOCUS_WINDOW_ID" ]; then
    "$NIRI" msg action focus-window --id "$FOCUS_WINDOW_ID"
  fi
fi

"$NOTIFY_SEND" "Session Restore" "$DISPLAY_NAME: Session restored"
