#!/usr/bin/env bash
# List sessions for fuzzy menu (projects with sessionApps + personal sessions)
# Dependencies: JQ, CONFIG_FILE (set via environment)

"$JQ" -r 'to_entries[] |
  {
    icon: "󰍹",
    label: .value.displayName,
    action: {exec: ["niri-session-restore", .key]}
  }' "$CONFIG_FILE" | "$JQ" -s '.'
