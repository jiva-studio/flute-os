#!/usr/bin/env bash
# Waybar module: status of every Claude agent across all workspaces.
#
# Reads the registry written by fluteos-agent-hook. Entries whose process is
# gone are pruned here rather than by the hook, because a SIGKILLed agent never
# gets to run SessionEnd — liveness has to be checked by an outside observer.
#
#   fluteos-agents-widget              render (waybar calls this)
#   fluteos-agents-widget --dismiss    clear every "waiting" flag, print nothing
#
# Dependencies: JQ, REGISTRY_DIR (required), NIRI (optional) — set via environment
# Optional: NUDGE_TTL (seconds) — see the ageing pass below.

set -u

mkdir -p "$REGISTRY_DIR"

# Rewrite one entry in place, atomically. A widget refresh must never leave a
# half-written registry file behind for the next reader.
downgrade() { # <file> <detail>
  local f="$1" detail="$2" tmp="$1.$$"
  "$JQ" --arg d "$detail" '.status = "idle" | .detail = $d' "$f" >"$tmp" 2>/dev/null \
    && mv -f "$tmp" "$f" || rm -f "$tmp"
}

# "I have seen all of them, stop blinking." Bound to a click on the chip: the
# flag means "an agent wants you", and only you can say that it no longer does.
if [ "${1:-}" = "--dismiss" ]; then
  for f in "$REGISTRY_DIR"/*.json; do
    [ -e "$f" ] || continue
    "$JQ" -e '.status == "waiting"' "$f" >/dev/null 2>&1 && downgrade "$f" "dismissed"
  done
  exit 0
fi

# Sweep leftover temp files from downgrade(). It writes "<entry>.$$" and
# renames, so a crash between the two leaves a stray behind — and since the
# prune loop below only globs *.json, those accumulated forever (the oldest
# found in the wild was three months old). Anything still being written is
# newer than a minute and is left alone.
find "$REGISTRY_DIR" -maxdepth 1 -name '*.json.*' -type f -mmin +1 -delete 2>/dev/null

# Prune dead sessions: no live pid -> the agent is gone regardless of what its
# last hook claimed.
for f in "$REGISTRY_DIR"/*.json; do
  [ -e "$f" ] || continue
  pid=$("$JQ" -r '.pid // empty' "$f" 2>/dev/null)
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"
  fi
done

# Age out idle nudges — and ONLY those.
#
# Two different things arrive as "waiting": Claude's "I have been quiet for a
# minute" notification, and a request for permission. The first is a reminder
# and stops being true on its own; the second is an agent standing still until
# you answer, and expiring it would leave the bar calm while work is blocked.
# The hook tells them apart in `.wait`, so only nudges get a shelf life.
NOW=$(date +%s)
for f in "$REGISTRY_DIR"/*.json; do
  [ -e "$f" ] || continue
  "$JQ" -e --argjson now "$NOW" --argjson ttl "${NUDGE_TTL:-600}" \
    '.status == "waiting" and (.wait // "nudge") == "nudge"
     and (($now - (.updated // $now)) > $ttl)' "$f" >/dev/null 2>&1 \
    && downgrade "$f" "nudge expired"
done

# Clear "waiting" on the agent you are currently looking at.
#
# Nothing in the hook chain retires a "waiting": a Notification (including
# Claude's idle nudge) sets it, and only the next UserPromptSubmit overwrites
# it. An agent that merely went quiet therefore screams for attention forever.
# Focus is the missing signal — if its niri window is focused right now, the
# notification has served its purpose and the flag is stale by definition.
#
# NUDGES ONLY, for the same reason the ageing pass above is nudges only:
# looking at a permission prompt is not answering it. Clearing that flag on
# focus leaves the bar calm while the agent stands still, and since nothing
# re-sends the notification it would never light up again. A permission wait
# ends when the agent moves — the next PreToolUse overwrites it — or when you
# explicitly say you have seen it (--dismiss).
#
# The downgrade is written back to the registry, not just applied to this
# render: the next poll re-reads these files, so an in-memory fix would flip
# straight back to waiting.
#
# NIRI is optional. Without it the check is skipped and the widget behaves
# exactly as before — no hard dependency on the compositor being reachable.
# The call is also skipped when nothing is waiting: this runs once a second,
# and spawning a compositor query per poll to answer "nothing to clear" is a
# process a second for no result.
FOCUSED=""
if [ -n "${NIRI:-}" ] && \
   "$JQ" -se 'any(.[]; .status == "waiting" and (.wait // "nudge") == "nudge")' \
     "$REGISTRY_DIR"/*.json >/dev/null 2>&1; then
  FOCUSED=$("$NIRI" msg --json windows 2>/dev/null \
    | "$JQ" -r 'first(.[] | select(.is_focused) | .id) // empty' 2>/dev/null)
fi

if [ -n "$FOCUSED" ]; then
  for f in "$REGISTRY_DIR"/*.json; do
    [ -e "$f" ] || continue
    # .window is stored as a string by the hook, niri reports a number — and it
    # is matched on its FIRST id, not compared whole. An older hook could write
    # two ids into that field ("6 7") when one wezterm process owned two
    # windows, and a whole-string compare can never equal a focused id, so
    # those agents were unclearable: focus them all day and the chip keeps
    # blinking. Entries written then are still on disk and outlive the fix.
    "$JQ" -e --arg w "$FOCUSED" \
      '.status == "waiting" and (.wait // "nudge") == "nudge"
       and (((.window // "") | tostring | split(" ") | first // "") == $w)' \
      "$f" >/dev/null 2>&1 || continue
    downgrade "$f" "seen"
  done
fi

ENTRIES=$("$JQ" -s '.' "$REGISTRY_DIR"/*.json 2>/dev/null)
[ -z "$ENTRIES" ] && ENTRIES="[]"

"$JQ" -nc --argjson a "$ENTRIES" --argjson now "$(date +%s)" \
  --arg cWaiting "${COLOR_WAITING:-#89b4fa}" \
  --arg cWorking "${COLOR_WORKING:-#a6e3a1}" \
  --arg cIdle    "${COLOR_IDLE:-#cdd6f4}" \
  --arg cOff     "${COLOR_OFF:-#585b70}" '
  def icon: {working:"󰜎", waiting:"󰀦", idle:"󰅶"}[.] // "󰚩";
  def ago($t): ($now - $t) as $d
    | if   $d < 60    then "\($d)s"
      elif $d < 3600  then "\($d / 60 | floor)m"
      else                 "\($d / 3600 | floor)h" end;

  # waiting first — those are the ones actually blocking you
  def rank: {waiting:0, working:1, idle:2}[.] // 3;
  ($a | sort_by(.status | rank)) as $agents

  | ($agents | map(select(.status == "working")) | length) as $working
  | ($agents | map(select(.status == "waiting")) | length) as $waiting
  | ($agents | length) as $total

  # Three dots. ALWAYS three, in a fixed order — waiting, working, idle — and a
  # state with no agents keeps its dot, greyed. The position is what tells you
  # which state you are looking at, so dropping a dot would shift the others and
  # make the chip unreadable at a glance.
  #
  #   ● blue, blinking   an agent is blocked on YOU
  #   ● green            agents are working
  #   ● white            agents are open and idle
  #   ● grey             nothing in that state
  #
  # No numbers: the chip only has to say whether anything wants you. How many
  # agents are in each state is what the tooltip is for.
  #
  # The blink is a colour swap on alternate seconds, not a CSS animation: this
  # chip is shared with the usage percentage, and CSS can only animate the whole
  # chip — which would mean flashing its background.
  | ($total - $waiting - $working) as $idle
  | ([ (if $waiting > 0
        then (if ($now % 2) == 0 then $cOff else $cWaiting end)
        else $cOff end),
       (if $working > 0 then $cWorking else $cOff end),
       (if $idle    > 0 then $cIdle    else $cOff end) ]
     | map("<span foreground=\"\(.)\">●</span>") | join(" ")) as $counts

  | {
      compact: $counts,

      # No glyph. This half of the chip used to lead with a robot, which said
      # "Claude" on a bar that now reports five providers and agents from
      # several of them — an icon that names one vendor is worse than none.
      # The provider labels ahead of these dots carry the identity.
      text: $counts,

      tooltip:
        if $total == 0 then "No agents"
        else ($agents | map(
          "\(.status | icon)  \(.name)"
          + (if .detail != "" then "\n     \(.detail)" else "" end)
          + "  ·  \(ago(.updated))"
        ) | join("\n"))
        end,

      # Style hook: colour the whole module by the most urgent state present.
      class: (if $waiting > 0 then "waiting"
              elif $working > 0 then "working"
              elif $total > 0 then "idle"
              else "empty" end),

      alt: ($total | tostring)
    }'
