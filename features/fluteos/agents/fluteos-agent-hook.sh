#!/usr/bin/env bash
# Universal Claude Code hook -> agent status registry.
#
# Invoked as: fluteos-agent-hook <EventName>, with the hook payload on stdin.
# Writes one JSON file per session to $REGISTRY_DIR/<session_id>.json. The
# waybar widget and fluteos-agent-send read that directory; nothing here talks
# to Claude, so this stays a pure observer.
#
# Runs on EVERY PreToolUse, so it must stay cheap: one jq pass, one atomic
# rename. No network, no subshell fan-out.
#
# Dependencies: JQ, REGISTRY_DIR (set via environment)

set -u

EVENT="${1:-}"
[ -z "$EVENT" ] && exit 0

PAYLOAD=$(cat)
[ -z "$PAYLOAD" ] && exit 0

SESSION=$("$JQ" -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null)
# No session id -> nothing we can key on. Exit 0: a hook must never break the
# agent it is observing.
[ -z "$SESSION" ] && exit 0

mkdir -p "$REGISTRY_DIR"
FILE="$REGISTRY_DIR/$SESSION.json"

# SessionEnd retires the entry. Everything else upserts.
if [ "$EVENT" = "SessionEnd" ]; then
  rm -f "$FILE"
  exit 0
fi

CWD=$("$JQ" -r '.cwd // empty' <<<"$PAYLOAD" 2>/dev/null)

# Map the hook event onto the coarse state the widget shows.
#   working — busy, don't interrupt
#   waiting — blocked on YOU (permission prompt or idle nudge)
#   idle    — finished its turn, ready for the next instruction
case "$EVENT" in
  SessionStart)                 STATUS="idle" ;;
  UserPromptSubmit|PreToolUse)  STATUS="working" ;;
  Notification|PermissionRequest) STATUS="waiting" ;;
  Stop)                         STATUS="idle" ;;
  *)                            STATUS="working" ;;
esac

# One-line "what is it doing" for the tooltip.
case "$EVENT" in
  PreToolUse)
    DETAIL=$("$JQ" -r '
      (.tool_name // "?") as $t
      | (.tool_input.command // .tool_input.file_path // .tool_input.pattern // "") as $a
      | if $a == "" then $t else "\($t): \($a)" end' <<<"$PAYLOAD" 2>/dev/null)
    ;;
  UserPromptSubmit)
    DETAIL=$("$JQ" -r '.prompt // ""' <<<"$PAYLOAD" 2>/dev/null)
    ;;
  Notification|PermissionRequest)
    DETAIL=$("$JQ" -r '.waitingFor // .message // "needs your decision"' <<<"$PAYLOAD" 2>/dev/null)
    ;;
  Stop)
    DETAIL="replied, waiting"
    ;;
  *)
    DETAIL=""
    ;;
esac
# Keep the registry small — tooltips truncate anyway.
DETAIL=$(printf '%.140s' "${DETAIL//$'\n'/ }")

# Routing keys, inherited from the environment of the claude process:
#   WEZTERM_PANE — the pane to send text into (set by wezterm per pane)
#   CLAUDE_PID   — the claude process, used by the widget for liveness
PANE="${WEZTERM_PANE:-}"
PID="${CLAUDE_PID:-$PPID}"

# The niri window that hosts this agent. NIRI_WINDOW_ID is set by the fish
# init, but only reaches sessions launched through an interactive fish — for
# anything else it arrives empty, which is why "окно не записано" happened.
# So derive it instead: niri reports the pid of each window (the terminal), and
# the agent is a descendant of one of them, so walk up the process tree until a
# pid matches. Resolved once per session and carried forward — `niri msg` is
# far too expensive for a hook that fires on every tool call.
WINDOW=""
[ -f "$FILE" ] && WINDOW=$("$JQ" -r '.window // empty' "$FILE" 2>/dev/null)
if [ -z "$WINDOW" ]; then
  WINDOW="${NIRI_WINDOW_ID:-}"
fi
if [ -z "$WINDOW" ] && [ -n "${NIRI:-}" ]; then
  WPIDS=$("$NIRI" msg --json windows 2>/dev/null \
    | "$JQ" -r '.[] | "\(.pid) \(.id)"' 2>/dev/null)
  if [ -n "$WPIDS" ]; then
    walk="$PID"
    for _ in $(seq 1 15); do
      { [ -z "$walk" ] || [ "$walk" = "0" ]; } && break
      hit=$(awk -v k="$walk" '$1==k{print $2; exit}' <<<"$WPIDS")
      [ -n "$hit" ] && { WINDOW="$hit"; break; }
      [ "$walk" = "1" ] && break
      # PPid from /proc/<pid>/status, not field 4 of /proc/<pid>/stat — the
      # comm field there can contain spaces and parentheses and shifts columns.
      walk=$(awk '/^PPid:/{print $2}' /proc/"$walk"/status 2>/dev/null)
    done
  fi
fi

# Human-facing name: the workspace this cwd belongs to, else the directory.
# Resolved once per session and then carried forward from the existing entry —
# this hook runs on every PreToolUse, so the registry lookup must not be on the
# hot path.
NAME=""
[ -f "$FILE" ] && NAME=$("$JQ" -r '.name // empty' "$FILE" 2>/dev/null)
if [ -z "$NAME" ] && [ -n "$CWD" ] && [ -n "${WORKSPACE_REGISTRY_CMD:-}" ]; then
  WS_REGISTRY=$($WORKSPACE_REGISTRY_CMD 2>/dev/null)
  if [ -n "$WS_REGISTRY" ] && [ -f "$WS_REGISTRY" ]; then
    NAME=$("$JQ" -r --arg d "$CWD" '
      [ .[] | select((.agentDir // "") == $d or (.cwd // "") == $d) ][0].displayName // empty
    ' "$WS_REGISTRY" 2>/dev/null)
  fi
fi
[ -z "$NAME" ] && NAME=$(basename "${CWD:-agent}")

TMP="$FILE.$$"
"$JQ" -n \
  --arg session "$SESSION" \
  --arg name    "$NAME" \
  --arg cwd     "$CWD" \
  --arg status  "$STATUS" \
  --arg event   "$EVENT" \
  --arg detail  "$DETAIL" \
  --arg pane    "$PANE" \
  --arg window  "$WINDOW" \
  --arg pid     "$PID" \
  --argjson ts  "$(date +%s)" \
  '{session:$session, name:$name, cwd:$cwd, status:$status, event:$event,
    detail:$detail, pane:$pane, window:$window, pid:$pid, updated:$ts}' \
  >"$TMP" 2>/dev/null && mv -f "$TMP" "$FILE"

exit 0
