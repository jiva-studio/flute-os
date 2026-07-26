# Get current workspace name
current_name=$($NIRI msg --json workspaces | \
  $JQ -r '.[] | select(.is_focused) | .name // ""')

# Read new name from user
printf "Workspace name"
[ -n "$current_name" ] && printf " [$current_name]"
printf ": "
read -r new_name

# If empty input and we have current name, clear it
if [ -z "$new_name" ]; then
  if [ -n "$current_name" ]; then
    $NIRI msg action unset-workspace-name
  fi
else
  $NIRI msg action set-workspace-name "$new_name"
fi
