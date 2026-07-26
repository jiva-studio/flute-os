#!/usr/bin/env bash
# Send a message to a running Claude agent without focusing its window.
#
#   fluteos-agent-send <name-fragment> <text...>
#   fluteos-agent-send --pick <text...>     # choose the agent via fuzzel
#
# There is no supported IPC into a live interactive Claude session, so this
# drives the TUI: wezterm cli send-text into the agent's pane. The pane id is
# recorded by fluteos-agent-hook from $WEZTERM_PANE.
#
# Dependencies: JQ, WEZTERM, FUZZEL, NOTIFY_SEND, REGISTRY_DIR (via environment)

set -u

die() { "$NOTIFY_SEND" -u critical "Agent send" "$1"; echo "$1" >&2; exit 1; }

TARGET="${1:-}"; shift || true
[ -z "$TARGET" ] && die "usage: fluteos-agent-send <name|--pick> <text...>"

TEXT="$*"
[ -z "$TEXT" ] && die "nothing to send — empty text"

AGENTS=$("$JQ" -s '.' "$REGISTRY_DIR"/*.json 2>/dev/null)
[ -z "$AGENTS" ] || [ "$AGENTS" = "[]" ] && die "no running agents"

# Only agents we can actually reach: a pane id is required for send-text.
AGENTS=$("$JQ" '[ .[] | select((.pane // "") != "") ]' <<<"$AGENTS")
[ "$AGENTS" = "[]" ] && die "no agent is bound to a wezterm pane"

if [ "$TARGET" = "--pick" ]; then
  CHOICE=$("$JQ" -r '.[] | "\(.name)\t\(.session)"' <<<"$AGENTS" \
    | "$FUZZEL" --dmenu --with-nth=1 --prompt="Agent: " \
      --horizontal-pad=8 --vertical-pad=6 --inner-pad=4 \
      --background="$BG" --text-color="$FG" \
      --selection-color="$SEL_BG" --selection-text-color="$SEL_FG" \
      --border-color="$BORDER" --border-width=2 --border-radius=5 \
      --font="$FONT") || exit 0
  SESSION=$(cut -f2 <<<"$CHOICE")
  PANE=$("$JQ" -r --arg s "$SESSION" '.[] | select(.session == $s) | .pane' <<<"$AGENTS")
  NAME=$("$JQ" -r --arg s "$SESSION" '.[] | select(.session == $s) | .name'  <<<"$AGENTS")
else
  # Case-insensitive substring match on the display name. Ambiguity is an
  # error, not a coin flip — sending a task to the wrong agent is expensive.
  MATCHES=$("$JQ" --arg q "${TARGET,,}" \
    '[ .[] | select((.name | ascii_downcase | contains($q)) or (.cwd | ascii_downcase | contains($q))) ]' \
    <<<"$AGENTS")
  COUNT=$("$JQ" 'length' <<<"$MATCHES")
  [ "$COUNT" -eq 0 ] && die "agent “$TARGET” not found"
  if [ "$COUNT" -gt 1 ]; then
    NAMES=$("$JQ" -r 'map(.name) | join(", ")' <<<"$MATCHES")
    die "“$TARGET” matches several: $NAMES"
  fi
  PANE=$("$JQ" -r '.[0].pane' <<<"$MATCHES")
  NAME=$("$JQ" -r '.[0].name' <<<"$MATCHES")
fi

[ -z "$PANE" ] && die "agent has no pane id"

# Two calls on purpose: --no-paste types the text as keystrokes (bracketed
# paste can be swallowed by the TUI), then a bare CR submits it.
printf '%s' "$TEXT" | "$WEZTERM" cli send-text --pane-id "$PANE" --no-paste \
  || die "failed to write to pane $PANE"
printf '\r' | "$WEZTERM" cli send-text --pane-id "$PANE" --no-paste

"$NOTIFY_SEND" "→ $NAME" "$TEXT"
