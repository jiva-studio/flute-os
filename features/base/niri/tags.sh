#!/usr/bin/env bash
# Niri window tags - assign tags to windows and quickly switch between them
# Tags are per-workspace: tag "1" on workspace A is independent from tag "1" on workspace B
# Dependencies: JQ, NIRI, NOTIFY_SEND (set via environment)

TAGS_FILE="$XDG_RUNTIME_DIR/niri-tags.json"

# Initialize file if it doesn't exist
[ -f "$TAGS_FILE" ] || echo '{}' > "$TAGS_FILE"

# Get focused window info (contains workspace_id)
FOCUSED=$("$NIRI" msg --json focused-window)
WORKSPACE_ID=$(echo "$FOCUSED" | "$JQ" -r '.workspace_id')

case "$1" in
  set)
    WINDOW_ID=$(echo "$FOCUSED" | "$JQ" -r '.id')
    if [ "$WINDOW_ID" != "null" ] && [ "$WORKSPACE_ID" != "null" ]; then
      KEY="$WORKSPACE_ID:$2"
      "$JQ" --arg key "$KEY" --arg id "$WINDOW_ID" '.[$key] = ($id | tonumber)' \
        "$TAGS_FILE" > "$TAGS_FILE.tmp" && mv "$TAGS_FILE.tmp" "$TAGS_FILE"
      "$NOTIFY_SEND" -t 1000 "Tag $2"
    fi
    ;;
  focus)
    KEY="$WORKSPACE_ID:$2"
    WINDOW_ID=$("$JQ" -r --arg key "$KEY" '.[$key] // empty' "$TAGS_FILE")
    if [ -n "$WINDOW_ID" ]; then
      "$NIRI" msg action focus-window --id "$WINDOW_ID"
    fi
    ;;
esac
