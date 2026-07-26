#!/usr/bin/env bash
# Generate JSON list of Brain folders for fuzzy menu
# Dependencies: JQ, GREP (set via environment)

brain_dir="${BRAIN_DIR:-$HOME/Documents/Brain}"
folders=()

for folder in "$brain_dir"/*/; do
  [ -d "$folder" ] || continue
  folder_name=$(basename "$folder")
  # Skip hidden directories and system folders
  [[ "$folder_name" == .* ]] && continue
  [[ "$folder_name" == "@eaDir" ]] && continue

  # Determine icon: emoji from name or default
  first_char=$(printf '%s' "$folder_name" | "$GREP" -oP '^\X' 2>/dev/null)
  byte_len=$(printf '%s' "$first_char" | wc -c)
  # Emoji typically 4+ bytes in UTF-8
  if [ "$byte_len" -ge 4 ]; then
    icon="$first_char"
    # Remove emoji and leading space from display name
    display_name="${folder_name#"$first_char"}"
    display_name="${display_name# }"
  else
    icon="󰠮"
    display_name="$folder_name"
  fi

  # URL-encode the vault name (full name with emoji) for obsidian://open?vault=
  encoded=$(printf '%s' "$folder_name" | "$JQ" -sRr @uri)
  url="obsidian://open?vault=$encoded"
  folders+=("$("$JQ" -n --arg icon "$icon" --arg name "$display_name" --arg url "$url" \
    '{icon:$icon, label:$name, action:{exec:["xdg-open",$url]}}')")
done

# Assemble into JSON array
printf '%s\n' "${folders[@]}" | "$JQ" -s '.'
