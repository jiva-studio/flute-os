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

## The registry — `fluteos-agent-list`

**Start here, always.** One command answers "who is running, in what state, and
what do I address them by":

```bash
fluteos-agent-list            # human table
fluteos-agent-list --json     # the same as JSON — use this one
```

```
ID    STATUS   AGE  WHERE    NAME                     DOING
b9be  waiting  2m   pane 2   Aviso                    Claude is waiting for your input
20d1  working  8s   pane 1   Aviso                    Edit: src/app.ts
17c3  idle     1h   no pane  Jiva Studio : Lectorium  replied, waiting
```

Every running agent registers itself through the `fluteos-agent-hook` hooks as
one JSON file in `~/.cache/fluteos/agents/*.json`; the command prunes entries
whose process is gone (a SIGKILLed agent never runs SessionEnd). Fields:

- `id` — **the handle. Address agents by this.** Short prefix of the session id,
  unique and never reused.
- `name` — display name = the **project** the agent runs in (e.g. `Aviso`).
  Several agents in the same project share it, so a name is not an address.
- `session` — Claude session UUID; also names the transcript under
  `~/.claude/projects/`.
- `pane` + `socket` — WezTerm pane and the mux server that owns it. **Both** are
  needed: agent windows are launched with `--always-new-process`, so pane ids
  repeat across windows and a bare pane id can address the wrong agent.
- `reachable` — false when the session has no controlling terminal (a background
  job, an SDK run). Such an agent is real and reports status, but there is no
  pane to type into, and `fluteos-agent-send` will refuse.
- `window` (niri, for focusing), `cwd`, `status` (`working`|`waiting`|`idle`),
  `pid`, `updated`.

Do not hand-roll `jq` over the registry directory, and do not read `pane` from
your own environment: `$WEZTERM_PANE` is inherited, so a session started from
inside another agent's Bash carries its **parent's** pane id.

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

`fluteos-agent-launch` runs `wezterm start --always-new-process`, so each agent
is its own wezterm process with its own mux — but that no longer makes it
unreachable. The registry records the **socket** next to the pane, and
`fluteos-agent-send` addresses that socket, so a launched agent takes messages
like any other. Launch it, then drive it by `id`.

## Send a message — `fluteos-agent-send`

Types text into a running agent's pane and presses Enter, **without stealing
focus**. Takes an `id` from `fluteos-agent-list` — or, if nothing answers to that
id, a case-insensitive substring of `name`/`cwd`.

```sh
fluteos-agent-send b9be "run the tests and show me the result"   # ← do this
fluteos-agent-send widgets "…"                        # name, when it is unique
fluteos-agent-send --pick "draft the PR description"  # human picks via fuzzel
```

**Address by `id`.** Names are project display names, so three agents in one
project are all called `Aviso`; a name that matches several is a hard error
rather than a coin flip, and the error prints the candidate ids to retry with:

```
“aviso” matches several — address one by id: b9be (Aviso, waiting); 20d1 (Aviso, working)
```

An agent with `no pane` (see `reachable` above) cannot be typed into at all —
`--prompt` at launch was its only inbox.

## Driving panes directly

`fluteos-agent-list` + `fluteos-agent-send <id>` covers launching and messaging,
including several agents in one project. Go one level down only when you need
something the registry does not do — above all **reading a reply back**, which
has no `fluteos-` command:

```sh
SOCK=$(fluteos-agent-list --json | jq -r '.[] | select(.id=="b9be") | .socket')
PANE=$(fluteos-agent-list --json | jq -r '.[] | select(.id=="b9be") | .pane')
WEZTERM_UNIX_SOCKET=$SOCK wezterm cli get-text --pane-id "$PANE" | tail -30
```

Always carry the socket with the pane id. Without it `wezterm cli` talks to
whichever mux your own environment points at, where pane 5 is somebody else's
agent. The alternative — spawning agents in your own mux — keeps one pane-id
space, at the cost of every agent dying with your terminal:

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
| list running agents | `fluteos-agent-list --json` (human: `fluteos-agent-list`) |
| launch in a project | `fluteos-agent-launch --workspace <g:p> --title <T> --prompt "<task>"` |
| message an agent | `fluteos-agent-send <id> "<text>"` — id from the list |
| message a specific pane | `WEZTERM_UNIX_SOCKET=<socket> wezterm cli send-text --pane-id <id> --no-paste`, then the same with `printf '\r'` |
| set a title | spawn `-- fish -i -C "set-tab-title '<T>'; claude"` (NOT `wezterm cli set-tab-title` — it's ignored by format-tab-title) |
| read a reply | `WEZTERM_UNIX_SOCKET=<socket> wezterm cli get-text --pane-id <pane> \| tail -n 40` |
| focus an agent window | `niri msg action focus-window --id <window>` |
