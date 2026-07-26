# Waybar source: emit pretty display name for the active workspace on $WAYBAR_OUTPUT_NAME.
# Resolves niri's raw workspace name through the workspaces registry; falls back to
# the raw name when the workspace has no registry entry, and to "Workspace <idx>"
# when niri reports no name at all.
OUTPUT="$WAYBAR_OUTPUT_NAME"

"$NIRI" msg event-stream | while read -r _line; do
  active=$("$NIRI" msg --json workspaces | \
    "$JQ" -r --arg out "$OUTPUT" '.[] | select(.output == $out and .is_active) | {name: (.name // ""), idx: .idx}')

  name=$(printf '%s' "$active" | "$JQ" -r '.name')
  idx=$(printf '%s' "$active" | "$JQ" -r '.idx')

  if [ -n "$name" ]; then
    pretty=$("$JQ" -r --arg id "$name" '.[$id].displayName // empty' "$REGISTRY")
    [ -n "$pretty" ] && label="$pretty" || label="$name"
    icon=$("$JQ" -r --arg id "$name" '.[$id].icon // empty' "$REGISTRY")
    if [ -n "$icon" ]; then
      prefix="$icon"
    else
      prefix='🖥️'
    fi
    printf '{"text": "%s %s", "class": "has-name"}\n' "$prefix" "$label"
  else
    printf '{"text": "🖥️ Workspace %s", "class": "no-name"}\n' "$idx"
  fi
done
