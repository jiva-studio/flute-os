#!/usr/bin/env bash
# Waybar module: status of every Claude agent across all workspaces.
#
# Reads the registry written by fluteos-agent-hook. Entries whose process is
# gone are pruned here rather than by the hook, because a SIGKILLed agent never
# gets to run SessionEnd — liveness has to be checked by an outside observer.
#
# Dependencies: JQ, REGISTRY_DIR (required), NIRI (optional) — set via environment

set -u

mkdir -p "$REGISTRY_DIR"

# Prune dead sessions: no live pid -> the agent is gone regardless of what its
# last hook claimed.
for f in "$REGISTRY_DIR"/*.json; do
  [ -e "$f" ] || continue
  pid=$("$JQ" -r '.pid // empty' "$f" 2>/dev/null)
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"
  fi
done

# Clear "waiting" on the agent you are currently looking at.
#
# Nothing in the hook chain retires a "waiting": a Notification (including
# Claude's idle nudge) sets it, and only the next UserPromptSubmit overwrites
# it. An agent that merely went quiet therefore screams for attention forever.
# Focus is the missing signal — if its niri window is focused right now, the
# notification has served its purpose and the flag is stale by definition.
#
# The downgrade is written back to the registry, not just applied to this
# render: the next poll re-reads these files, so an in-memory fix would flip
# straight back to waiting.
#
# NIRI is optional. Without it the check is skipped and the widget behaves
# exactly as before — no hard dependency on the compositor being reachable.
FOCUSED=""
if [ -n "${NIRI:-}" ]; then
  FOCUSED=$("$NIRI" msg --json windows 2>/dev/null \
    | "$JQ" -r 'first(.[] | select(.is_focused) | .id) // empty' 2>/dev/null)
fi

if [ -n "$FOCUSED" ]; then
  for f in "$REGISTRY_DIR"/*.json; do
    [ -e "$f" ] || continue
    # .window is stored as a string by the hook, niri reports a number.
    "$JQ" -e --arg w "$FOCUSED" \
      '.status == "waiting" and ((.window // "") | tostring) == $w' \
      "$f" >/dev/null 2>&1 || continue
    tmp="$f.$$"
    "$JQ" '.status = "idle" | .detail = "seen"' "$f" >"$tmp" 2>/dev/null \
      && mv -f "$tmp" "$f" || rm -f "$tmp"
  done
fi

ENTRIES=$("$JQ" -s '.' "$REGISTRY_DIR"/*.json 2>/dev/null)
[ -z "$ENTRIES" ] && ENTRIES="[]"

"$JQ" -nc --argjson a "$ENTRIES" --argjson now "$(date +%s)" '
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

  # One dot per state, and only for states that HAVE agents.
  #
  # This used to be three bare numbers in a fixed order, "1/1/5", where the
  # position carried the whole meaning — unreadable unless you already knew the
  # order, and the third slot (idle) was routinely mistaken for something
  # alarming. The shape now says which state it is, so nothing has to be
  # remembered and empty states can simply be dropped:
  #
  #   ◉2   two agents are waiting on YOU        (the chip blinks blue)
  #   ●3   three are working                    (the chip pulses green)
  #   ○5   five are open and idle               (chip keeps the usage colour)
  #
  # Shape, not only colour: the chip has one background at a time, and a bar is
  # a bad place to demand colour discrimination.
  | ($total - $waiting - $working) as $idle
  | ([ (if $waiting > 0 then "◉\($waiting)" else empty end),
       (if $working > 0 then "●\($working)" else empty end),
       (if $idle    > 0 then "○\($idle)"    else empty end) ]
     | join(" ")) as $counts

  | {
      compact: (if $total == 0 then "" else $counts end),

      text: (if $total == 0 then "" else "󰚩 " + $counts end),

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
