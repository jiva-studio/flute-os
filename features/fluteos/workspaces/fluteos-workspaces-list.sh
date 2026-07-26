#!/usr/bin/env bash
# Emit JSON list of workspaces for fuzzy menu.
# Output format: [{icon, label, action: {exec: ["fluteos-workspace-open", "<id>"]}}, ...]
# Uses .value.icon (from project effective config) when set, else generic glyph.
#
# Dependencies: JQ, REGISTRY (set via environment)

"$JQ" '
  to_entries
  | sort_by(.value.displayName)
  | map({
      icon: (if (.value.icon // "") != "" then .value.icon else "󰆍" end),
      label: .value.displayName,
      action: { exec: ["fluteos-workspace-open", .key] }
    })
' "$REGISTRY"
