# Two styled fuzzel popups on the agent keybinding: which agent to start, then
# an optional session title. Hands off to fluteos-agent-launch, which sets the
# wezterm tab_title OSC from the title and runs the profile's command in
# cwd/agentDir.
#
# Esc at either step → silent exit. Enter on an empty title → launch untitled.
# A catalogue with one profile skips the first popup entirely, so an install
# that never set features.fluteos.workspaces.agentProfiles sees the old flow.
#
# Dependencies: FUZZEL, JQ, PROFILES and the fuzzel theme vars (via environment)

fuzzel_menu() {
  "$FUZZEL" --dmenu "$@" \
    --horizontal-pad=8 --vertical-pad=6 --inner-pad=4 \
    --background="$BG" --text-color="$FG" \
    --selection-color="$SEL_BG" --selection-text-color="$SEL_FG" \
    --border-color="$BORDER" --border-width=2 --border-radius=5 \
    --font="$FONT"
}

PROFILE=""
COUNT=$("$JQ" 'length' "$PROFILES" 2>/dev/null || echo 0)

if [ "$COUNT" -gt 1 ]; then
  # Display column first, id after a tab: --with-nth=1 shows and matches only
  # the label, so typing "glm" finds the profile without the id polluting it.
  CHOICE=$("$JQ" -r '
    to_entries
    | sort_by(.value.order, .value.name)[]
    | "\(if .value.icon == "" then "" else .value.icon + "  " end)\(.value.name)\t\(.key)"
  ' "$PROFILES" | fuzzel_menu --with-nth=1 --prompt="Agent: ") || exit 0
  PROFILE=$(printf '%s' "$CHOICE" | cut -f2)
  [ -z "$PROFILE" ] && exit 0
fi

TITLE=$(fuzzel_menu --lines=0 --width=40 --prompt="Title: " </dev/null) || exit 0

if [ -n "$PROFILE" ]; then
  exec fluteos-agent-launch --agent "$PROFILE" --title "$TITLE"
fi
exec fluteos-agent-launch "$TITLE"
