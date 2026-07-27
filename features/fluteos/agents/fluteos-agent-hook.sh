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

PID="${CLAUDE_PID:-$PPID}"

# --- routing: the pane this session can actually be typed into ---------------
#
# NOT $WEZTERM_PANE. That variable is inherited like any other, so a session
# started from inside another agent's Bash carries its PARENT's pane id, and
# text addressed here lands in somebody else's conversation. Worse, pane ids
# are per-mux-server, and fluteos-agent-launch starts every window with
# --always-new-process: three agents can all legitimately be "pane 0".
#
# So derive it from something the process cannot inherit — its own controlling
# terminal — and record the socket that owns it:
#   tpgid > 0 and pgrp == tpgid  → this process is the FOREGROUND program of a
#                                  controlling tty, i.e. it owns a pane
#   tpgid == -1                  → no controlling tty (a background job, an SDK
#                                  session): no pane exists, and saying
#                                  otherwise is how messages get misrouted
# then match that tty against wezterm's own pane list (`tty_name`).
#
# Resolved ONCE per session and carried forward: this hook runs on every
# PreToolUse and `wezterm cli list` has no business on that path.
PANE=""; SOCKET=""; TTY=""; ROUTED=""
if [ -f "$FILE" ]; then
  eval "$("$JQ" -r '@sh "ROUTED=\(.routed // "") PANE=\(.pane // "") SOCKET=\(.socket // "") TTY=\(.tty // "")"' "$FILE" 2>/dev/null)"
fi

if [ -z "$ROUTED" ]; then
  ROUTED="1"
  # /proc/<pid>/stat, parsed after the last ")" — the comm field can contain
  # spaces and parentheses, which shifts every column when split naively.
  STAT=$(cat "/proc/$PID/stat" 2>/dev/null)
  STAT=${STAT#*") "}
  # after the strip: 1 state, 2 ppid, 3 pgrp, 4 session, 5 tty_nr, 6 tpgid
  # shellcheck disable=SC2086
  set -- $STAT
  PGRP="${3:-0}"; TPGID="${6:--1}"

  if [ "$TPGID" -gt 0 ] 2>/dev/null && [ "$PGRP" = "$TPGID" ]; then
    for fd in 0 1 2; do
      link=$(readlink "/proc/$PID/fd/$fd" 2>/dev/null)
      case "$link" in /dev/pts/*) TTY="$link"; break ;; esac
    done
  fi

  if [ -n "$TTY" ] && [ -n "${WEZTERM:-}" ]; then
    # The env socket first (right in the common case, one call), then every
    # other live mux — a pane's tty is unique across all of them, so the first
    # hit is the answer and there is nothing to disambiguate.
    for sock in "${WEZTERM_UNIX_SOCKET:-}" "$XDG_RUNTIME_DIR"/wezterm/gui-sock-*; do
      [ -n "$sock" ] && [ -e "$sock" ] || continue
      hit=$(WEZTERM_UNIX_SOCKET="$sock" "$WEZTERM" cli list --format json 2>/dev/null \
        | "$JQ" -r --arg t "$TTY" 'first(.[] | select(.tty_name == $t) | .pane_id) // empty' 2>/dev/null)
      if [ -n "$hit" ]; then PANE="$hit"; SOCKET="$sock"; break; fi
    done
  fi
fi

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

# Short handle to address this agent by. The session id is unique and never
# reused, so its prefix inherits both properties; four characters are enough to
# type and long enough that a clash needs 65k concurrent agents. On a clash
# with a DIFFERENT session the full id is used instead of picking a winner.
ID=""
[ -f "$FILE" ] && ID=$("$JQ" -r '.id // empty' "$FILE" 2>/dev/null)
if [ -z "$ID" ]; then
  ID="${SESSION:0:4}"
  for other in "$REGISTRY_DIR"/*.json; do
    [ -e "$other" ] || continue
    [ "$other" = "$FILE" ] && continue
    if [ "$("$JQ" -r '.id // empty' "$other" 2>/dev/null)" = "$ID" ]; then
      ID="$SESSION"
      break
    fi
  done
fi

TMP="$FILE.$$"
"$JQ" -n \
  --arg id      "$ID" \
  --arg session "$SESSION" \
  --arg name    "$NAME" \
  --arg cwd     "$CWD" \
  --arg status  "$STATUS" \
  --arg event   "$EVENT" \
  --arg detail  "$DETAIL" \
  --arg pane    "$PANE" \
  --arg socket  "$SOCKET" \
  --arg tty     "$TTY" \
  --arg routed  "$ROUTED" \
  --arg window  "$WINDOW" \
  --arg pid     "$PID" \
  --argjson ts  "$(date +%s)" \
  '{id:$id, session:$session, name:$name, cwd:$cwd, status:$status, event:$event,
    detail:$detail, pane:$pane, socket:$socket, tty:$tty, routed:$routed,
    window:$window, pid:$pid, updated:$ts,
    # Derived, not stated: an agent is reachable exactly when a pane and the
    # mux that owns it are both known. Consumers must not re-derive this.
    reachable: (($pane != "") and ($socket != ""))}' \
  >"$TMP" 2>/dev/null && mv -f "$TMP" "$FILE"

exit 0
