---
name: fluteos-agent-run
description: Launch real Claude agents in their own WezTerm windows, send them messages, title their tabs, and read their replies — a fleet of terminal agents, NOT the built-in Task/subagent tool. Wraps the fluteos agent subsystem (fluteos-agent-launch, fluteos-agent-send) plus raw `wezterm cli` for same-project agents. Use whenever the task is "launch an agent / spawn an agent / open an agent in a new window / send a message to an agent / tell agent X / set the agent window title / open Claude in a new window".
---

## What this is

A way to spin up **separate, real `claude` processes**, each in its own WezTerm
window, and drive them from here: give each a task, a tab title, send follow-up
messages, and read back what they answered. This is **not** the built-in
`Agent`/`Task` subagent tool — those are in-process and headless. These are
full interactive Claude sessions the user can also watch and type into.

There is **no supported IPC** into a live interactive Claude session, so
"sending a message" means driving the TUI: type keystrokes into the agent's
WezTerm pane, then a bare Enter to submit.

## The registry

Every running agent registers itself (via the `fluteos-agent-hook` Stop/Start
hooks) as one JSON file in `~/.cache/fluteos/agents/*.json`. Fields:

- `name` — display name = the **project** the agent runs in (e.g. `Aviso`).
  Several agents in the same project therefore share a name.
- `session` — Claude session UUID (unique per agent).
- `pane` — WezTerm pane id — **this is what you send/read through**.
- `window` — WezTerm window id (for focusing via niri).
- `cwd`, `status` (`working`|`idle`|…), `pid`, `updated`.

Inspect: `jq -s '[.[]|{name,session,pane,window,status,cwd}]' ~/.cache/fluteos/agents/*.json`
Or ask WezTerm directly: `wezterm cli list`.

## Launch an agent — `fluteos-agent-launch`

Opens `claude` in a **new WezTerm window** in the workspace's `agentDir`, sets
the tab title, and tiles the column. Workspace ids come from the workspaces
registry (`fluteos-workspaces-registry-path` → JSON keyed `group:project`, e.g.
`acme:acme`, `acme:widgets`).

```sh
# In a specific project, with a title and an initial task (starts working immediately):
fluteos-agent-launch --workspace acme:acme --title "Docs" --prompt "refresh the architecture docs"

# In the currently focused workspace, title only (legacy positional form):
fluteos-agent-launch "Scratch"
```

- `--title` sets the WezTerm `tab_title` OSC user var — highest priority in the
  `format-tab-title` chain (see `wezterm/project-badges.nix`), so it wins over
  the `Claude:` kind label.
- `--prompt` hands the task on argv so the agent starts on it, not at an empty
  prompt.
- Omit `--workspace` to use the focused niri workspace. Never launch more than
  ~3–4 at once (they tile to columns).

⚠️ **`fluteos-agent-launch` runs `wezterm start --always-new-process` — every
agent it starts is its OWN wezterm process with its OWN mux. Your `wezterm cli`
(and `fluteos-agent-send`) only see YOUR mux, so a launched agent is invisible
from here: it registers as `pane: "0"` and you can NOT send to it or read it
back.** The `--prompt` at launch is the ONLY message you can ever deliver to it.
In practice you almost always end up sending an agent more messages, so this is
the wrong default — **default to the raw-spawn-in-your-mux path below**, which
keeps every agent addressable. Reserve `fluteos-agent-launch` for a genuinely
fire-and-forget agent, or one only the human at the keyboard will drive.

## Send a message — `fluteos-agent-send`

Types text into a running agent's pane and presses Enter, **without stealing
focus**. Matches the agent by case-insensitive substring of its `name` or `cwd`.

```sh
fluteos-agent-send widgets "run the tests and show me the result"
fluteos-agent-send --pick "draft the PR description"   # choose via fuzzel
```

Ambiguity is a hard error (won't guess between two matches). Since same-project
agents share a `name`, `fluteos-agent-send Aviso …` fails when >1 Aviso agent is
up — use the **raw pane** path below for those.

## Several agents in the same project → drive panes directly

**This is the default way to run agents you orchestrate.** You will keep sending
them messages, so spawn them **in your own mux** with `wezterm cli spawn` and
keep each pane id — that list is your only handle on the fleet. (`fluteos-agent-launch`
would put each in a separate mux at `pane: "0"`, unreachable from here, and
`fluteos-agent-send` can't tell same-`name` agents apart anyway — there is no
way to recover an addressable handle after the fact, so capture pane ids now.)

```sh
# 1) spawn — set the title INSIDE the pane's shell before exec'ing claude, then
#    capture the pane id `wezterm cli spawn` prints. The title is the OSC user
#    var `tab_title`, emitted by the `set-tab-title` fish function — this is the
#    ONLY thing the format-tab-title handler reads. `wezterm cli set-tab-title`
#    sets just the mux tab title, which the handler IGNORES, so it does NOT set
#    the displayed title here (this is exactly how fluteos-agent-launch does it):
PANE=$(wezterm cli spawn --new-window --cwd "$HOME/Projects/acme/acme/agent" -- \
  fish -i -C "set-tab-title 'Pushkin'; claude")

# 2) send a message: type text, then a bare CR to submit (two calls on purpose —
#    --no-paste types keystrokes; bracketed paste can be swallowed by the TUI):
printf '%s' "your message" | wezterm cli send-text --pane-id "$PANE" --no-paste
sleep 1; printf '\r'       | wezterm cli send-text --pane-id "$PANE" --no-paste

# 3) read its reply back:
wezterm cli get-text --pane-id "$PANE" | grep -v '^[[:space:]]*$' | tail -30
```

Keep the three pane ids (e.g. in shell vars or a note) — that list IS your only
handle on the fleet. To title AND task each in one shot, put both in the fish
init: `fish -i -C "set-tab-title 'TICKET-123 slow query'; claude 'your task…'"`.

Give a fresh `claude` ~5–6 s to reach its prompt before sending the first
message. If a pane already has half-typed text in its input box (the user was
typing), clear it first with Ctrl-U: `printf '\025' | wezterm cli send-text --pane-id "$PANE" --no-paste`.

## Titles — the contract

The WezTerm title chain (`wezterm/project-badges.nix`) reads OSC 1337
`SetUserVar`, in priority order:

1. `tab_title` — manual override. Set ONLY by emitting the OSC user var from
   **inside the agent's shell**: the fish function `set-tab-title "My Title"`
   (or `fluteos-agent-launch --title`, which runs exactly that in the pane's
   fish init before exec'ing claude).
2. `agent_session` — a session label the agent emits.
3. `agent_kind` — `Claude`/`OpenCode`, emitted by the `claude` wrapper on start.

⚠️ `wezterm cli set-tab-title` does NOT work here. It sets the mux tab title,
but `format-tab-title` recomputes the displayed title from the `tab_title` user
var on every render and overrides it — so a CLI-set title is silently discarded
and the tab falls back to `agent_kind` (`Claude`). Set the user var, not the mux
title: spawn `claude` under `fish -i -C "set-tab-title '…'; claude"`.

## Cheat sheet

| want | command |
|------|---------|
| list running agents | `jq -s '[.[]\|{name,pane,status}]' ~/.cache/fluteos/agents/*.json` / `wezterm cli list` |
| launch in a project | `fluteos-agent-launch --workspace <g:p> --title <T> --prompt "<task>"` |
| message by name | `fluteos-agent-send <name\|cwd-fragment> "<text>"` |
| message a specific pane | `printf '%s' "<t>" \| wezterm cli send-text --pane-id <id> --no-paste; sleep 1; printf '\r' \| wezterm cli send-text --pane-id <id> --no-paste` |
| set a title | spawn `-- fish -i -C "set-tab-title '<T>'; claude"` (NOT `wezterm cli set-tab-title` — it's ignored by format-tab-title) |
| read a reply | `wezterm cli get-text --pane-id <id> \| tail -n 40` |
| focus an agent window | `niri msg action focus-window --id <window>` |
