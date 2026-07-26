# Close the focused workspace: close all its windows and clear its name,
# so niri reaps the now-empty unnamed workspace (named ones never collapse).
ws_id=$($NIRI msg --json workspaces | $JQ -r '.[] | select(.is_focused) | .id')
[ -z "$ws_id" ] && exit 0

# Close every window that lives on this workspace
$NIRI msg --json windows | \
  $JQ -r --argjson ws "$ws_id" '.[] | select(.workspace_id == $ws) | .id' | \
  while read -r wid; do
    [ -n "$wid" ] && $NIRI msg action close-window --id "$wid"
  done

# Drop the name so the emptied workspace collapses
$NIRI msg action unset-workspace-name
