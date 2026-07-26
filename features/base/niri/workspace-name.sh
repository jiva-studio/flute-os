OUTPUT="$WAYBAR_OUTPUT_NAME"
$NIRI msg event-stream | while read -r line; do
  # Parse workspace events and output name for the specific monitor
  name=$($NIRI msg --json workspaces | \
    $JQ -r --arg out "$OUTPUT" '.[] | select(.output == $out and .is_active) | .name // empty')

  if [ -n "$name" ]; then
    printf '{"text": "<span size='"'"'16pt'"'"' rise='"'"'-2pt'"'"'>󰍹</span> %s", "class": "has-name"}\n' "$name"
  else
    # Show workspace index when no name
    idx=$($NIRI msg --json workspaces | \
      $JQ -r --arg out "$OUTPUT" '.[] | select(.output == $out and .is_active) | .idx')
    printf '{"text": "<span size='"'"'16pt'"'"' rise='"'"'-2pt'"'"'>󰍹</span> Workspace %s", "class": "no-name"}\n' "$idx"
  fi
done
