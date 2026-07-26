#!/usr/bin/env bash
# Launch the workspace's agent (claude|opencode) in agentDir.
#
#   fluteos-agent-launch [TITLE]
#   fluteos-agent-launch --workspace <id> --title <t> --prompt <task>
#
# TITLE is set via OSC user_var tab_title and wins over agent_kind/agent_session
# in the wezterm format-tab-title chain. The bare positional form is kept for the
# existing keybinding and fluteos-agent-prompt callers.
#
# --workspace targets a workspace other than the focused one, so a voice command
# can start an agent in a project you are not currently looking at.
# --prompt hands the agent its task on the command line, so it starts working
# immediately instead of waiting at an empty input.
#
# Dependencies: JQ, NIRI, WEZTERM, REGISTRY (set via environment)

# Three agents should tile to a full screen, so the share must divide 100
# exactly — 33% left a visible gap on the third column.
AGENT_COLUMN_WIDTH="${FLUTEOS_AGENT_COLUMN_WIDTH:-33.333%}"

TITLE=""
PROMPT=""
WS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS="${2:-}"; shift 2 ;;
    --title)     TITLE="${2:-}"; shift 2 ;;
    --prompt)    PROMPT="${2:-}"; shift 2 ;;
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

# Build fish init: optionally set the tab title first, then exec the agent under
# direnv, optionally with the task as its first argument.
FISH_INIT="direnv exec '$DIR' $CMD"
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
