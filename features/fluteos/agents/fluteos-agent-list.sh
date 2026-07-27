#!/usr/bin/env bash
# List the running Claude agents — the fleet, as one command.
#
#   fluteos-agent-list            human table
#   fluteos-agent-list --json     the registry as a JSON array, for agents
#
# This is the answer to "which agents are running and where can I send text",
# and it exists so that nobody — human or model — has to hand-roll jq over
# ~/.cache/fluteos/agents/*.json and then guess at the fields. The `id` column
# is what fluteos-agent-send takes.
#
# Dead entries are pruned here, not by the hook: an agent killed with SIGKILL
# never runs SessionEnd, so liveness can only be established from outside.
#
# Dependencies: JQ, REGISTRY_DIR (via environment)

set -u

JSON=0
case "${1:-}" in
  --json) JSON=1 ;;
  "") ;;
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "usage: fluteos-agent-list [--json]" >&2; exit 2 ;;
esac

mkdir -p "$REGISTRY_DIR"

for f in "$REGISTRY_DIR"/*.json; do
  [ -e "$f" ] || continue
  pid=$("$JQ" -r '.pid // empty' "$f" 2>/dev/null)
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"
  fi
done

AGENTS=$("$JQ" -s 'sort_by(.name, .updated)' "$REGISTRY_DIR"/*.json 2>/dev/null)
[ -z "$AGENTS" ] && AGENTS="[]"

if [ "$JSON" = "1" ]; then
  printf '%s\n' "$AGENTS"
  exit 0
fi

if [ "$AGENTS" = "[]" ]; then
  echo "no agents running"
  exit 0
fi

# `reachable` is only present on entries written by a current hook; treat a
# missing field as "old entry, work it out from pane+socket" so an upgrade does
# not blank the column for sessions that were already running.
NOW=$(date +%s)
"$JQ" -r --argjson now "$NOW" '
  def age: (($now - (.updated // $now)) | if . < 60 then "\(.)s"
            elif . < 3600 then "\(. / 60 | floor)m"
            else "\(. / 3600 | floor)h" end);
  def reach: if (.reachable // ((.pane // "") != "" and (.socket // "") != ""))
             then "pane \(.pane)" else "no pane" end;
  ["ID","STATUS","AGE","WHERE","NAME","DOING"],
  (.[] | [ (.id // (.session // "")[0:4]), .status, age, reach, .name,
           ((.detail // "") | .[0:60]) ])
  | @tsv' <<<"$AGENTS" | column -t -s $'\t'

# A closing note rather than a column: the reason an agent has no pane is
# always the same one, and it is not obvious.
if "$JQ" -e 'any(.[]; (.reachable // ((.pane // "") != "" and (.socket // "") != "")) | not)' <<<"$AGENTS" >/dev/null; then
  echo
  echo "“no pane” = the session has no controlling terminal (a background job or"
  echo "an SDK session). It is running and reporting status, but text cannot be"
  echo "typed into it — fluteos-agent-send has nowhere to send."
fi
