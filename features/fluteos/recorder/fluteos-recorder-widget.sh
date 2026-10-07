#!/usr/bin/env bash
# Waybar module: the meeting recorder.
#
# One glance has to answer "is this meeting being recorded?", so the state lives
# in the ICON and its colour, not in the chip's background — the bar's colours
# belong to the layout (see waybar/style.nix), and a chip that changes colour
# with runtime status makes the whole bar twitch.
#
#   󰍬  idle          click to start
#   󰑊  recording     red, with how long
#   󰏤  paused
#   󰔟  transcribing
#   󰀦  aborted       ffmpeg died — the audio so far is on disk
#
# Dependencies: JQ RECORD COLOR_REC COLOR_WARN (via environment)

set -u

S=$("$RECORD" status --json 2>/dev/null)
[ -z "$S" ] && S='{"state":"idle","human":"","label":"","dir":""}'

"$JQ" -c --arg cRec "${COLOR_REC:-#d20f39}" --arg cWarn "${COLOR_WARN:-#df8e1d}" '
  def dot($c; $g): "<span foreground=\"\($c)\">\($g)</span>";
  (if .label != "" then .label else (.dir | split("/") | last // "") end) as $name
  | if .state == "recording" then
      { text: (dot($cRec; "󰑊") + " " + .human), class: "recording",
        tooltip: "Recording \($name) · \(.human)\n\nClick: stop and transcribe\nMiddle: pause\nRight: open the folder" }
    elif .state == "paused" then
      { text: ("󰏤 " + .human), class: "paused",
        tooltip: "Paused at \(.human) · \($name)\n\nMiddle: resume\nClick: stop and transcribe" }
    elif .state == "transcribing" then
      { text: "󰔟", class: "transcribing",
        tooltip: "Transcribing \($name)…\n\nThe audio is already saved." }
    elif .state == "aborted" then
      { text: dot($cWarn; "󰀦"), class: "aborted",
        tooltip: "Recording stopped unexpectedly · \($name)\nEverything up to that point is on disk.\n\nClick: finish it off" }
    else
      { text: "󰍬", class: "idle",
        tooltip: "Record this meeting\n\nSaves into the workspace resources folder,\nthen sends it for transcription." }
    end' <<<"$S"
