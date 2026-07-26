new_name="$1"
if [ -z "$new_name" ]; then
  $NIRI msg action unset-workspace-name
else
  $NIRI msg action set-workspace-name "$new_name"
fi
