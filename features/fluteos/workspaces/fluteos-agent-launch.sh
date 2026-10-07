#!/usr/bin/env bash
# Launch the workspace's agent (claude|opencode) in agentDir.
#
#   fluteos-agent-launch [TITLE]
#   fluteos-agent-launch --workspace <id> --title <t> --prompt <task> --agent <id>
#
# TITLE is set via OSC user_var tab_title and wins over agent_kind/agent_session
# in the wezterm format-tab-title chain. The bare positional form is kept for the
# existing keybinding and fluteos-agent-prompt callers.
#
# --workspace targets a workspace other than the focused one, so a voice command
# can start an agent in a project you are not currently looking at.
# --prompt hands the agent its task on the command line, so it starts working
# immediately instead of waiting at an empty input.
# --agent names a profile from features.fluteos.workspaces.agentProfiles: its
# command replaces the workspace's agentCommand for this launch, and its env/
# envFiles are exported first. Omitted, the workspace's own agent is used, so
# every existing caller behaves exactly as before.
#
# Dependencies: JQ, NIRI, WEZTERM, REGISTRY, PROFILES (set via environment)

# Three agents should tile to a full screen, so the share must divide 100
# exactly — 33% left a visible gap on the third column.
AGENT_COLUMN_WIDTH="${FLUTEOS_AGENT_COLUMN_WIDTH:-33.333%}"

TITLE=""
PROMPT=""
WS=""
AGENT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS="${2:-}"; shift 2 ;;
    --title)     TITLE="${2:-}"; shift 2 ;;
    --prompt)    PROMPT="${2:-}"; shift 2 ;;
    --agent)     AGENT="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *)  # Positional: legacy title form.
        [ -z "$TITLE" ] && TITLE="$1"; shift ;;
  esac
done

if [ -z "$WS" ]; then
  WS=$("$NIRI" msg --json workspaces 2>/dev/null \
    | "$JQ" -r '.[] | select(.is_focused) | .name // empty')
fi

[ -z "$WS" ] && exit 1

# agentDir is always populated by workspaces/default.nix (eff.agentDir). Fall
# back to nothing — if it's missing, the registry is malformed and we'd rather
# fail loudly than silently cd into an unrelated directory.
DIR=$("$JQ" -r --arg id "$WS" '.[$id].agentDir // empty' "$REGISTRY")
if [ -z "$DIR" ]; then
  echo "fluteos-agent-launch: workspace '$WS' has no agentDir in registry" >&2
  exit 1
fi

CMD=$("$JQ" -r --arg id "$WS" '.[$id].agentCommand // "claude"' "$REGISTRY")

# Escape for single-quoted fish strings: 'foo' -> 'foo\''  (close, escape, reopen).
fq() { printf "%s" "${1//\'/\'\\\'\'}"; }

# A named profile replaces the workspace's agent and brings its own environment.
# Unknown id is fatal rather than silently falling back: a typo in a keybinding
# would otherwise start the wrong backend on someone's subscription.
ENV_INIT=""
if [ -n "$AGENT" ]; then
  PROFILE=$("$JQ" -c --arg id "$AGENT" '.[$id] // empty' "${PROFILES:-/dev/null}" 2>/dev/null)
  if [ -z "$PROFILE" ]; then
    echo "fluteos-agent-launch: no agent profile '$AGENT' in $PROFILES" >&2
    exit 1
  fi
  CMD=$("$JQ" -r '.command' <<<"$PROFILE")

  # Plain values first, then the file-backed ones — a key is read at launch, so
  # it lives in the agent's environment and nowhere else. An unreadable path
  # leaves the variable unset on purpose: the provider then says "unauthorized",
  # which is a far clearer failure than a shell error on a missing file.
  while IFS=$'\t' read -r VAR VAL; do
    [ -z "$VAR" ] && continue
    ENV_INIT="$ENV_INIT set -gx '$(fq "$VAR")' '$(fq "$VAL")'; "
  done < <("$JQ" -r '(.env // {}) | to_entries[] | "\(.key)\t\(.value)"' <<<"$PROFILE")

  while IFS=$'\t' read -r VAR FILE; do
    [ -z "$VAR" ] && continue
    ENV_INIT="$ENV_INIT test -r '$(fq "$FILE")'; and set -gx '$(fq "$VAR")' (cat '$(fq "$FILE")' | string trim); "
  done < <("$JQ" -r '(.envFiles // {}) | to_entries[] | "\(.key)\t\(.value)"' <<<"$PROFILE")
fi

# Build fish init: optionally set the tab title first, then export the profile's
# environment, then exec the agent under direnv, optionally with the task as its
# first argument.
FISH_INIT="$ENV_INIT""direnv exec '$DIR' $CMD"
[ -n "$PROMPT" ] && FISH_INIT="$FISH_INIT '$(fq "$PROMPT")'"
[ -n "$TITLE" ]  && FISH_INIT="set-tab-title '$(fq "$TITLE")'; $FISH_INIT"

# Clear the nested-session markers Claude Code exports into child processes.
# Without this, an agent launched from inside another agent's Bash inherits
# CLAUDE_CODE_CHILD_SESSION=1 and treats itself as a sub-session — which turns
# OFF transcript saving, so those agents' transcripts are silently lost. A
# launched agent is a real top-level session, so start it from a clean slate
# (same markers fluteos-agent-command.sh already strips before `claude -p`).
env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION \
  "$WEZTERM" --config enable_tab_bar=true start --always-new-process --cwd "$DIR" \
  -- fish -i -C "$FISH_INIT" &

# Wait for window to appear, then set column width
sleep 0.5
"$NIRI" msg action set-column-width "$AGENT_COLUMN_WIDTH"
