import { execSync } from "child_process"
import { writeFileSync } from "fs"

function findWindow(sessionTitle) {
  const windows = JSON.parse(execSync("niri msg -j windows").toString())
  return windows.find(w => {
    if (!w.title) return false
    if (w.title === `OC | ${sessionTitle}`) return true
    if (w.title.startsWith(`OC | ${sessionTitle.slice(0, 20)}`)) return true
    return w.title.includes(sessionTitle)
  })
}

function setUrgent(windowId) {
  execSync(`niri msg action set-window-urgent --id ${windowId}`)
}

// Tell the terminal (wezterm) about the agent state via OSC 1337 SetUserVar.
// Written to /dev/tty so the OpenCode TUI's stdout doesn't get corrupted.
function emitUserVar(name, value) {
  try {
    const b64 = Buffer.from(value, "utf-8").toString("base64")
    writeFileSync("/dev/tty", `\x1b]1337;SetUserVar=${name}=${b64}\x07`)
  } catch (_) {}
}

export const NotifyPlugin = async ({ client }) => {
  const pendingIdle = new Set()
  const announcedSessions = new Set()

  // Mark this pane as running OpenCode for the terminal title contract.
  emitUserVar("agent_kind", "opencode")

  return {
    event: async ({ event }) => {
      try {
        if (event.type === "session.idle" || event.type === "session.updated") {
          const sessionID = event.properties.sessionID

          // Push session title to the tab (once per session, when title becomes available).
          if (!announcedSessions.has(sessionID)) {
            const sessions = await client.session.list()
            const session = sessions.data?.find(s => s.id === sessionID)
            if (session?.title && !session.title.startsWith("New session")) {
              announcedSessions.add(sessionID)
              emitUserVar("agent_session", session.title)
            }
          }
        }

        if (event.type === "session.idle") {
          const sessionID = event.properties.sessionID
          const sessions = await client.session.list()
          const session = sessions.data?.find(s => s.id === sessionID)

          if (session?.title && !session.title.startsWith("New session")) {
            const match = findWindow(session.title)
            if (match) setUrgent(match.id)
          } else {
            pendingIdle.add(sessionID)
          }
        }

        if (event.type === "session.updated") {
          const sessionID = event.properties.sessionID
          if (!pendingIdle.has(sessionID)) return

          const sessions = await client.session.list()
          const session = sessions.data?.find(s => s.id === sessionID)

          if (session?.title && !session.title.startsWith("New session")) {
            pendingIdle.delete(sessionID)
            const match = findWindow(session.title)
            if (match) setUrgent(match.id)
          }
        }
      } catch (_) {}
    },
  }
}
