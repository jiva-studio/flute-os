#!/usr/bin/env bash
# Pick a running agent from fuzzel and focus its window. Bound to the waybar
# module's on-click, so the widget doubles as a jump list.
#
# Dependencies: JQ, NIRI, FUZZEL, NOTIFY_SEND, REGISTRY_DIR (via environment)

set -u

AGENTS=$("$JQ" -s '.' "$REGISTRY_DIR"/*.json 2>/dev/null)
if [ -z "$AGENTS" ] || [ "$AGENTS" = "[]" ]; then
  "$NOTIFY_SEND" "Agents" "No running agents"
  exit 0
fi

CHOICE=$("$JQ" -r '
  def icon: {working:"󰜎", waiting:"󰀦", idle:"󰅶"}[.] // "󰚩";
  def rank: {waiting:0, working:1, idle:2}[.] // 3;
  sort_by(.status | rank)[]
  | "\(.status | icon)  \(.name)\t\(.window)"
' <<<"$AGENTS" | "$FUZZEL" --dmenu --with-nth=1 --prompt="Agent: " \
  --horizontal-pad=8 --vertical-pad=6 --inner-pad=4 \
  --background="$BG" --text-color="$FG" \
  --selection-color="$SEL_BG" --selection-text-color="$SEL_FG" \
  --border-color="$BORDER" --border-width=2 --border-radius=5 \
  --font="$FONT") || exit 0

WINDOW=$(cut -f2 <<<"$CHOICE")
if [ -z "$WINDOW" ] || [ "$WINDOW" = "null" ]; then
  "$NOTIFY_SEND" "Agents" "No niri window recorded for this agent"
  exit 0
fi

"$NIRI" msg action focus-window --id "$WINDOW"
