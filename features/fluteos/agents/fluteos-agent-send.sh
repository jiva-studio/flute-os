#!/usr/bin/env bash
# Send a message to a running Claude agent without focusing its window.
#
#   fluteos-agent-send <id> <text...>            ← the reliable form
#   fluteos-agent-send <name-fragment> <text...>
#   fluteos-agent-send --pick <text...>          # choose the agent via fuzzel
#
# Get the ids from `fluteos-agent-list`. Names are display names of workspaces
# and are NOT unique — three agents in the same project are all called after it,
# which is why a name that matches several is an error here and always will be.
#
# There is no supported IPC into a live interactive Claude session, so this
# drives the TUI: wezterm cli send-text into the agent's pane. Both the pane and
# the mux socket that owns it come from fluteos-agent-hook, which derives them
# from the session's controlling terminal — pane ids are per-mux-server, so a
# pane id alone would address a different agent in another window.
#
# Dependencies: JQ, WEZTERM, FUZZEL, NOTIFY_SEND, REGISTRY_DIR (via environment)

set -u

die() { "$NOTIFY_SEND" -u critical "Agent send" "$1"; echo "$1" >&2; exit 1; }

TARGET="${1:-}"; shift || true
[ -z "$TARGET" ] && die "usage: fluteos-agent-send <id|name|--pick> <text...>"

TEXT="$*"
[ -z "$TEXT" ] && die "nothing to send — empty text"

AGENTS=$("$JQ" -s '.' "$REGISTRY_DIR"/*.json 2>/dev/null)
[ -z "$AGENTS" ] || [ "$AGENTS" = "[]" ] && die "no running agents"

# Only agents we can actually reach: send-text needs both a pane and the mux
# server that owns it. A session without a controlling terminal (a background
# job, an SDK run) is a real agent and shows up in fluteos-agent-list, but it
# has no pane to type into.
AGENTS=$("$JQ" '[ .[] | select((.pane // "") != "" and (.socket // "") != "") ]' <<<"$AGENTS")
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
  MATCHES=$("$JQ" --arg s "$SESSION" '[ .[] | select(.session == $s) ]' <<<"$AGENTS")
else
  # An exact id wins outright — that is the whole point of having one. Only if
  # nothing answers to that id does this fall back to matching display names,
  # where ambiguity is an error rather than a coin flip: sending a task to the
  # wrong agent costs more than a failed command.
  MATCHES=$("$JQ" --arg q "$TARGET" '[ .[] | select(.id == $q or .session == $q) ]' <<<"$AGENTS")
  if [ "$("$JQ" 'length' <<<"$MATCHES")" -eq 0 ]; then
    MATCHES=$("$JQ" --arg q "${TARGET,,}" \
      '[ .[] | select((.name | ascii_downcase | contains($q)) or (.cwd | ascii_downcase | contains($q))) ]' \
      <<<"$AGENTS")
  fi
  COUNT=$("$JQ" 'length' <<<"$MATCHES")
  [ "$COUNT" -eq 0 ] && die "agent “$TARGET” not found — run fluteos-agent-list"
  if [ "$COUNT" -gt 1 ]; then
    # Print what to retry WITH, not just that it failed: the ids are the fix.
    CANDIDATES=$("$JQ" -r 'map("\(.id) (\(.name), \(.status))") | join("; ")' <<<"$MATCHES")
    die "“$TARGET” matches several — address one by id: $CANDIDATES"
  fi
fi

PANE=$("$JQ" -r '.[0].pane'   <<<"$MATCHES")
SOCKET=$("$JQ" -r '.[0].socket' <<<"$MATCHES")
NAME=$("$JQ" -r '.[0].name'   <<<"$MATCHES")

[ -z "$PANE" ] || [ "$PANE" = "null" ] && die "agent has no pane id"
[ -z "$SOCKET" ] || [ "$SOCKET" = "null" ] && die "agent has no mux socket"

# Address the mux server that owns the pane, not whichever one this process
# happens to have inherited: fluteos-agent-launch starts every agent window
# with --always-new-process, so pane ids repeat across windows.
export WEZTERM_UNIX_SOCKET="$SOCKET"

# Two calls on purpose: --no-paste types the text as keystrokes (bracketed
# paste can be swallowed by the TUI), then a bare CR submits it.
printf '%s' "$TEXT" | "$WEZTERM" cli send-text --pane-id "$PANE" --no-paste \
  || die "failed to write to pane $PANE"
printf '\r' | "$WEZTERM" cli send-text --pane-id "$PANE" --no-paste

"$NOTIFY_SEND" "→ $NAME" "$TEXT"
