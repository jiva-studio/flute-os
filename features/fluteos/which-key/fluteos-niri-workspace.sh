$NIRI msg --json workspaces 2>/dev/null | \
  $JQ -r '.[] | select(.is_focused) | .name // empty'
