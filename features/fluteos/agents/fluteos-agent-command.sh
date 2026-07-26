#!/usr/bin/env bash
# Voice command router: turns a dictated phrase into ONE desktop action.
#
#   fluteos-agent-command "<transcribed spoken phrase>"
#
# Everything is decided by the model. It is handed the current workspaces,
# running agents, installed apps and the attach state, and returns ONE json
# object from a fixed action set. The model gets NO tools — we dispatch each
# action ourselves from a whitelist, so a misheard phrase can never become an
# arbitrary command.
#
# Sticky dictation ("attach"): once attached to an agent, a plain phrase becomes
# a "dictate" action and its text is typed into that agent's pane. Attaching,
# detaching and dictating are all model decisions — there is no separate parser.
#
# Dependencies: JQ, NIRI, CLAUDE, FLOCK, NOTIFY_SEND, REGISTRY_DIR, TARGET_FILE,
# APP_REGISTRY, WORKSPACE_REGISTRY_CMD (via environment)

set -u

# Drop the pay-per-use API key for the whole router and everything it spawns.
# The PTT service exports ANTHROPIC_API_KEY for translate/grammar, and children
# inherit it — but agents launched here (and the router's own claude -p) must go
# through the claude.ai subscription. With the key set, a launched agent opens
# with the "Both claude.ai and ANTHROPIC_API_KEY set" warning and the router's
# call fails hard when the key is stale.
unset ANTHROPIC_API_KEY

TEXT="${*:-}"
[ -z "$TEXT" ] && exit 0

# Trail of what was heard, what the model decided and what ran. PTT dispatches
# this detached, so a failure here leaves no trace anywhere else — without a log
# a silent no-op is undebuggable. Kept to the last 200 lines.
LOG="${LOG_FILE:-/tmp/fluteos-agent-command.log}"
log() {
  printf '%s  %s\n' "$(date '+%H:%M:%S')" "$1" >>"$LOG" 2>/dev/null
  if [ "$(wc -l <"$LOG" 2>/dev/null || echo 0)" -gt 200 ]; then
    tail -n 100 "$LOG" >"$LOG.t" 2>/dev/null && mv -f "$LOG.t" "$LOG"
  fi
}

say() {
  log "-> $1"
  "$NOTIFY_SEND" -h "string:x-canonical-private-synchronous:ptt" "Command" "$1"
}

# Serialise the whole router. PTT dispatches detached, so a phrase spoken while
# the previous one is still routing would run concurrently: two send-text calls
# into one pane interleave their keystrokes, and a slow lookup could act on a
# target a later command already replaced. Queue instead of reject — dictating
# two sentences in a row is normal and both should arrive, in order.
if [ -z "${FLUTEOS_CMD_LOCKED:-}" ]; then
  export FLUTEOS_CMD_LOCKED=1
  # The lock lives next to the target file, and nothing here creates that
  # directory — only the agent hook does. Before any agent had ever registered,
  # flock could not create the lock and the first voice command reported "Busy".
  mkdir -p "$(dirname "$TARGET_FILE")"
  # `-E 75` gives lock-not-acquired its own exit code. Without it flock exits 1,
  # which is indistinguishable from the inner script exiting 1 — so every
  # command that produced no summary line (a "status" query, an `action:"none"`
  # reply) was announced as "Busy with the previous command", and because that
  # notification carries the same synchronous hint it REPLACED the answer the
  # user had just asked for.
  # Re-exec through bash: $0 is a plain store file with no execute bit, so
  # handing it to flock directly fails with EACCES.
  "$FLOCK" -w 45 -E 75 "${TARGET_FILE}.lock" bash "$0" "$@"
  rc=$?
  [ "$rc" -eq 75 ] && say "Busy with the previous command"
  exit "$rc"
fi

log "HEARD: $TEXT"

agents_json() { "$JQ" -s '.' "$REGISTRY_DIR"/*.json 2>/dev/null || echo '[]'; }

# ---- context handed to the model -------------------------------------------

WS_REGISTRY=$($WORKSPACE_REGISTRY_CMD 2>/dev/null)
WS_LIST="[]"
[ -n "$WS_REGISTRY" ] && [ -f "$WS_REGISTRY" ] && \
  WS_LIST=$("$JQ" -c '[ .[] | {id, name: .displayName} ]' "$WS_REGISTRY" 2>/dev/null)

AG_LIST=$(agents_json | "$JQ" -c '[ .[] | {name, status} ]')

APP_LIST="[]"
[ -n "${APP_REGISTRY:-}" ] && [ -f "$APP_REGISTRY" ] && \
  APP_LIST=$("$JQ" -c '[ .[].label ]' "$APP_REGISTRY" 2>/dev/null)

# Name of the agent dictation is currently attached to (empty when detached),
# so the model can tell "dictate to it" from "attach/detach/other command".
ATTACHED=""
if [ -f "$TARGET_FILE" ]; then
  S=$(cat "$TARGET_FILE" 2>/dev/null)
  ATTACHED=$(agents_json | "$JQ" -r --arg s "$S" '.[] | select(.session == $s) | .name' 2>/dev/null)
  # Attached agent is gone: drop the stale target so we don't misroute.
  [ -z "$ATTACHED" ] && rm -f "$TARGET_FILE"
fi

say "…"

PROMPT=$(cat <<EOF
You route ONE spoken desktop command to actions. Reply with ONE json
object and nothing else — no prose, no code fence.

Workspaces: $WS_LIST
Running agents: $AG_LIST
Applications: $APP_LIST
Currently dictating to agent: ${ATTACHED:-null}

Reply shape: {"actions":[ <one or more action objects> ]}. A command may ask
for several things at once — put one action object per thing, in the order they
should run.

Action objects:
{"action":"launch_app","label":"<application label>"}
{"action":"open_workspace","id":"<workspace id>"}
{"action":"launch_agents","agents":[{"workspace":"<workspace id>","prompt":"<task>","title":"<2-3 word label>"}]}
{"action":"send","target":"<agent name>","text":"<message>"}
{"action":"attach","target":"<agent name>"}
{"action":"detach"}
{"action":"dictate","text":"<message>"}
{"action":"focus_agent","target":"<agent name>"}
{"action":"status"}
{"action":"browser","url":"<url>"}
{"action":"close_window"}
{"action":"none","reason":"<short why, English>"}

Rules:
- The command is transcribed speech and may be distorted — match ids/names by
  sound to the closest entry in the lists above. Never invent an id.
- "attach" starts sticky dictation to an agent ("switch to X", "talk to X");
  "detach" stops it ("detach", "stop").
- If "Currently dictating to agent" is not null and the phrase is not itself a
  command, use one dictate action — it goes to that agent verbatim. Keep the
  agent-facing text (dictate/prompt) in the language it was spoken.
- launch_agents takes ONE ENTRY PER AGENT, each with its own task. Never launch
  more than 4 agents total.
- If nothing matches confidently, use a single "none" action with a reason.

Examples (shape only):
"launch two agents in acme, one updates docs, the other writes code" ->
{"actions":[{"action":"launch_agents","agents":[
  {"workspace":"acme:acme","prompt":"update the docs","title":"Docs"},
  {"workspace":"acme:acme","prompt":"write code","title":"Code"}]}]}
"open obsidian and launch firefox" ->
{"actions":[{"action":"launch_app","label":"Obsidian"},
            {"action":"launch_app","label":"Firefox"}]}

Command: $TEXT
EOF
)

# Ask the model, with a hard timeout so a hung call can't wedge the flock and
# freeze every later command. The nested-session markers are cleared because
# with them set, claude -p refuses to answer. (ANTHROPIC_API_KEY is already
# unset for the whole process, see top of file.)
#
# claude -p over the subscription errors intermittently ("Execution error" on
# stderr) — retry once before giving up, and capture stderr to the log instead
# of /dev/null so a real failure is diagnosable rather than a silent no-op.
ask_model() {
  timeout 30 env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION \
    "$CLAUDE" -p "$PROMPT" --model haiku </dev/null 2>>"$LOG"
}
RAW=$(ask_model)
if [ -z "$RAW" ] || grep -qi 'execution error' <<<"$RAW"; then
  log "MODEL RETRY (first attempt: ${RAW:-empty})"
  sleep 1
  RAW=$(ask_model)
fi
if [ $? -ne 0 ] && [ -z "$RAW" ]; then
  log "MODEL TIMED OUT OR FAILED"
  say "No answer from the model"; exit 0
fi

# The model is asked for a bare object but may wrap it in a ```json fence.
CLEAN=$(grep -v '^[[:space:]]*```' <<<"$RAW")
JSON=$("$JQ" -c '.' <<<"$CLEAN" 2>/dev/null)
if [ -z "$JSON" ]; then
  # Salvage the outermost {...}; collapse newlines so the match spans a
  # pretty-printed object.
  JSON=$(tr -d '\n' <<<"$CLEAN" | grep -o '{.*}' | head -1)
  JSON=$("$JQ" -c '.' <<<"$JSON" 2>/dev/null)
fi
if [ -z "$JSON" ]; then
  log "UNPARSEABLE MODEL OUTPUT: $RAW"
  say "Didn't understand the command"; exit 0
fi
log "DECISION: $JSON"

# Normalise to a list. The model is asked for {"actions":[...]}, but tolerate a
# bare single action object too, so a stray old-shape reply still runs.
ACTIONS=$("$JQ" -c 'if .actions then .actions elif .action then [.] else [] end' <<<"$JSON")
COUNT=$("$JQ" 'length' <<<"$ACTIONS" 2>/dev/null || echo 0)
if [ "$COUNT" -eq 0 ]; then
  say "Didn't understand the command"; exit 0
fi

# Resolve a spoken name to one agent. Prints "name<TAB>pane<TAB>window".
resolve_agent() {
  agents_json | "$JQ" -r --arg q "$1" '
    [ .[] | select(.name == $q or (.name | ascii_downcase | contains($q | ascii_downcase))) ]
    | if length >= 1 then .[0] | "\(.name)\t\(.pane)\t\(.window)" else empty end'
}

# Execute ONE action object (passed as $1, compact json). Uses `return`, never
# `exit`: one bad action must not abort the rest of the list. Appends a short
# human phrase to the RESULTS array for the final summary notification.
RESULTS=()
dispatch_one() {
  local J="$1" a
  a=$("$JQ" -r '.action // "none"' <<<"$J")
  case "$a" in
    launch_app)
      local LBL; LBL=$("$JQ" -r '.label // empty' <<<"$J")
      [ -z "$LBL" ] && { RESULTS+=("?app"); return; }
      # Run the whitelisted argv for this label — the model supplies only a name
      # we already trust, never a command line.
      local ARGV; mapfile -t ARGV < <("$JQ" -r --arg l "$LBL" \
        '.[] | select(.label == $l) | .exec[]' "$APP_REGISTRY" 2>/dev/null)
      [ "${#ARGV[@]}" -eq 0 ] && { RESULTS+=("“$LBL”?"); return; }
      setsid "${ARGV[@]}" >/dev/null 2>&1 &
      RESULTS+=("$LBL") ;;

    open_workspace)
      local ID; ID=$("$JQ" -r '.id // empty' <<<"$J")
      [ -z "$ID" ] && { RESULTS+=("?ws"); return; }
      fluteos-workspace-open "$ID" && RESULTS+=("$ID") ;;

    launch_agents)
      local n; n=$("$JQ" '(.agents // []) | length' <<<"$J")
      [ "$n" -gt 4 ] 2>/dev/null && n=4
      while IFS=$'\t' read -r WS P T; do
        [ -z "$WS" ] && continue
        fluteos-agent-launch --workspace "$WS" --title "${T:-Agent}" --prompt "$P"
        RESULTS+=("${T:-agent}")
        sleep 0.4
      done < <("$JQ" -r --argjson n "$n" \
        '.agents[:$n][] | "\(.workspace // "")\t\(.prompt // "")\t\(.title // "")"' <<<"$J") ;;

    send)
      local T M; T=$("$JQ" -r '.target // empty' <<<"$J"); M=$("$JQ" -r '.text // empty' <<<"$J")
      { [ -z "$T" ] || [ -z "$M" ]; } && { RESULTS+=("?send"); return; }
      fluteos-agent-send "$T" "$M" && RESULTS+=("-> $T") ;;

    attach)
      local T; T=$("$JQ" -r '.target // empty' <<<"$J")
      local HIT; if HIT=$(resolve_agent "$T"); [ -n "$HIT" ]; then
        local NAME SID; NAME=$(cut -f1 <<<"$HIT")
        SID=$(agents_json | "$JQ" -r --arg n "$NAME" '.[] | select(.name == $n) | .session' | head -1)
        printf '%s' "$SID" > "$TARGET_FILE"; ATTACHED="$NAME"
        RESULTS+=("attach $NAME")
      else
        RESULTS+=("“$T”?")
      fi ;;

    detach)
      rm -f "$TARGET_FILE"; ATTACHED=""; RESULTS+=("detached") ;;

    dictate)
      local M; M=$("$JQ" -r '.text // empty' <<<"$J")
      [ -z "$ATTACHED" ] && { RESULTS+=("not attached"); return; }
      [ -z "$M" ] && return
      fluteos-agent-send "$ATTACHED" "$M" && RESULTS+=("-> $ATTACHED") ;;

    focus_agent)
      local T; T=$("$JQ" -r '.target // empty' <<<"$J")
      local HIT; if HIT=$(resolve_agent "$T"); [ -n "$HIT" ]; then
        local W; W=$(cut -f3 <<<"$HIT")
        [ -n "$W" ] && { "$NIRI" msg action focus-window --id "$W"; RESULTS+=("focus $(cut -f1 <<<"$HIT")"); } \
                    || RESULTS+=("no window")
      else
        RESULTS+=("“$T”?")
      fi ;;

    status)
      local SUM; SUM=$(agents_json | "$JQ" -r '
        if length == 0 then "No agents"
        else map("\(.name): \(.status)") | join("\n") end')
      say "$SUM" ;;

    browser)
      local U; U=$("$JQ" -r '.url // empty' <<<"$J")
      [ -z "$U" ] && { RESULTS+=("?url"); return; }
      fluteos-workspace-browser "$U" && RESULTS+=("$U") ;;

    close_window)
      "$NIRI" msg action close-window; RESULTS+=("closed") ;;

    *)
      say "$("$JQ" -r '.reason // "Didn'\''t understand the command"' <<<"$J")" ;;
  esac
}

# Run each action in order. jq -c streams one compact object per line.
while IFS= read -r one; do
  [ -z "$one" ] && continue
  log "RUN: $one"
  dispatch_one "$one"
done < <("$JQ" -c '.[]' <<<"$ACTIONS")

# One summary notification for the whole batch (status/none already notified).
# An `if` and an explicit exit, not a `&&` one-liner: as the script's last
# command, a false test became the script's exit status.
if [ "${#RESULTS[@]}" -gt 0 ]; then
  say "$(IFS=', '; echo "${RESULTS[*]}")"
fi
exit 0
