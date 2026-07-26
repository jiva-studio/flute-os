# Pop a styled fuzzel single-line prompt for an optional agent session title,
# then hand off to fluteos-agent-launch (which sets the wezterm tab_title OSC
# from $1 and launches the workspace's agent in cwd/agentDir).
# Esc → silent exit. Enter on empty input → launch without manual title.
TITLE=$("$FUZZEL" --dmenu --lines=0 --width=40 --prompt="Agent: " \
  --horizontal-pad=8 --vertical-pad=6 --inner-pad=4 \
  --background="$BG" --text-color="$FG" \
  --selection-color="$SEL_BG" --selection-text-color="$SEL_FG" \
  --border-color="$BORDER" --border-width=2 --border-radius=5 \
  --font="$FONT" </dev/null) || exit 0

exec fluteos-agent-launch "$TITLE"
