#!/usr/bin/env bash
# Meeting recorder: the command surface.
#
#   fluteos-record start [label]     begin recording into the current workspace
#   fluteos-record stop              finish, write metadata, queue transcription
#   fluteos-record pause | resume    close the current segment / open the next
#   fluteos-record toggle [--prompt] what the bar chip is bound to
#   fluteos-record pause-toggle
#   fluteos-record status [--json]
#   fluteos-record last              print the last recording's directory
#   fluteos-record transcribe [dir]  (re)transcribe — also works on old ones
#   fluteos-record open [dir]
#   fluteos-record live             reopen the live transcript window
#
# The recording is a systemd unit, not a child of this script: closing the
# terminal, the bar, or the session that started it must not take the meeting
# with it.
#
# Dependencies: JQ NIRI NOTIFY_SEND FFPROBE SYSTEMCTL SYSTEMD_RUN PKILL FUZZEL
#   XDG_OPEN TRANSCRIBE_SCRIPT DEEPGRAM_KEY_FILE AUTO_TRANSCRIBE FALLBACK_DIR
#   DIR_NAME MIN_FREE_MB LAST_FILE WORKSPACE_REGISTRY_CMD LIVE_ENABLED
#   LIVE_WINDOW (via environment)

set -u

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/fluteos-record"
STATE="$STATE_DIR/state.json"
TRANSCRIBE_STATE="$STATE_DIR/transcribing.json"
UNIT="fluteos-record.service"
LIVE_UNIT="fluteos-record-live.service"
# RTMIN+14 — see features/fluteos/waybar/modules.nix for the allocation.
BAR_SIGNAL=14

notify() { [ -n "${NOTIFY_SEND:-}" ] && "$NOTIFY_SEND" "$@" >/dev/null 2>&1; return 0; }
die() { echo "$1" >&2; notify -u critical "Recorder" "$1"; exit 1; }
refresh_bar() { "$PKILL" -SIGRTMIN+"$BAR_SIGNAL" waybar >/dev/null 2>&1; return 0; }

recording() { "$SYSTEMCTL" --user is-active --quiet "$UNIT"; }

# --- the live half ----------------------------------------------------------
#
# Ordering is the whole of it: the streaming client makes the pipe and opens
# the read end, THEN ffmpeg opens the write end. Started the other way round,
# the encoder would sit waiting on an interpreter's start-up with a meeting
# already in progress.
#
# Every one of these is best-effort. Live transcription failing to start is a
# reason to say so; it is never a reason to not record.
live_enabled() { [ "${LIVE_ENABLED:-0}" = "1" ] && [ -n "${DEEPGRAM_KEY_FILE:-}" ]; }

live_start() {
  live_enabled || return 0
  if ! "$SYSTEMCTL" --user start "$LIVE_UNIT" >/dev/null 2>&1; then
    notify -u critical "Live transcription" "did not start — recording anyway"
    return 0
  fi
  # The unit being "started" only means systemd forked it; the socket appears a
  # Python start-up later, and the capture skips the live output if it is not
  # there yet. Two seconds is generous for that and short enough that nobody
  # waits on it to begin a meeting.
  local waited=0
  while [ ! -S "$STATE_DIR/live.sock" ] && [ "$waited" -lt 20 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
}

live_stop() {
  live_enabled || return 0
  "$SYSTEMCTL" --user stop "$LIVE_UNIT" >/dev/null 2>&1
  return 0
}

# What ends a live session is stopping the unit: the client takes SIGTERM as
# "the meeting is over", tells Deepgram to flush, and writes the last words
# before exiting. It cannot infer this from the audio — ffmpeg drops and
# reconnects over a long meeting, and a client that ended at the first close
# would transcribe the opening minutes and nothing more.
live_finish() {
  live_enabled || return 0
  "$SYSTEMCTL" --user stop "$LIVE_UNIT" >/dev/null 2>&1
  return 0
}

# The window goes when the meeting does. It is a view of a recording in
# progress, and one left standing after the recording stopped is a window
# showing something that is no longer happening — `fluteos-record live` opens
# it again over the transcript on disk when that is what you want.
live_window_close() {
  "$SYSTEMCTL" --user stop fluteos-record-live-window.service >/dev/null 2>&1
  return 0
}

live_window() { # <dir>
  live_enabled || return 0
  [ -n "${LIVE_WINDOW:-}" ] || return 0
  "$SYSTEMD_RUN" --user --quiet --collect --unit=fluteos-record-live-window \
    --description="Live transcript window" \
    "$LIVE_WINDOW" "$1" >/dev/null 2>&1
  return 0
}
sget() { "$JQ" -r --arg k "$1" '.[$k] // ""' "$STATE" 2>/dev/null; }

# mm:ss / h:mm — hours matter for a meeting, seconds do not.
human_time() { # <seconds>
  local s="${1:-0}"
  if [ "$s" -lt 3600 ]; then printf '%dm' $((s / 60));
  else printf '%dh%02d' $((s / 3600)) $(((s % 3600) / 60)); fi
}

# Seconds of audio actually captured: wall clock since the start, minus every
# pause. Cheap on purpose — the alternative, probing the segments, would run
# ffprobe on every bar refresh.
elapsed_now() {
  local started paused_total paused_at now
  started=$(sget started); paused_total=$(sget pausedTotal); paused_at=$(sget pausedAt)
  now=$(date +%s)
  [ -z "$started" ] && { echo 0; return; }
  if [ "${paused_at:-0}" -gt 0 ]; then now="$paused_at"; fi
  echo $((now - started - ${paused_total:-0}))
}

# --- where a new recording goes ---------------------------------------------
#
# The workspace decides, and it decides ONCE, at the start: switching projects
# mid-meeting must not move the file that is being written into.
#
# niri names a workspace by its registry id, which is what the workspaces
# registry is keyed on — so the focused workspace resolves straight to the
# project's resources directory. Without a workspace (or without the registry)
# the fallback is used, because losing an hour of audio to "no project here" is
# not a trade anyone would take.
resolve_target() { # <label> -> sets TARGET_DIR, WS_ID
  local label="$1" res="" base="" reg="" slug=""
  WS_ID=$("$NIRI" msg --json workspaces 2>/dev/null \
    | "$JQ" -r 'first(.[] | select(.is_focused) | .name // "") // ""' 2>/dev/null)

  if [ -n "$WS_ID" ] && [ -n "${WORKSPACE_REGISTRY_CMD:-}" ]; then
    reg=$($WORKSPACE_REGISTRY_CMD 2>/dev/null)
    [ -n "$reg" ] && [ -f "$reg" ] \
      && res=$("$JQ" -r --arg id "$WS_ID" '.[$id].resourcesDir // ""' "$reg" 2>/dev/null)
  fi

  if [ -n "$res" ]; then base="$res/$DIR_NAME"; else base="$FALLBACK_DIR"; fi

  # A label is a filename, so it is treated as hostile input: no separators, no
  # traversal, no control characters. Bash slicing (not `cut -c`) keeps the
  # truncation on character boundaries — `cut` counts bytes and would leave half
  # a Cyrillic letter at the end.
  slug="${label,,}"
  slug="${slug//[[:space:]]/-}"
  slug="${slug//\//-}"
  slug="${slug//\\/-}"
  slug="${slug//../}"
  slug="${slug//[[:cntrl:]]/}"
  slug="${slug:0:40}"
  slug="${slug#-}"; slug="${slug%-}"

  TARGET_DIR="$base/$(date +%Y-%m-%d-%H%M)${slug:+-$slug}"
  # Two meetings starting inside the same minute is unlikely and harmless to
  # handle; appending to somebody else's directory is neither.
  local n=2
  while [ -e "$TARGET_DIR" ]; do TARGET_DIR="${TARGET_DIR%-[0-9]*}-$n"; n=$((n + 1)); done
}

cmd_start() {
  local label="${1:-}"
  recording && die "already recording — stop it first"
  if [ -f "$STATE" ]; then
    # Two different situations, and telling them apart is the difference
    # between "press resume" and "your last meeting is half-saved, deal with
    # it": a state file without a running unit means ffmpeg died.
    if [ "$(sget pausedAt)" != "0" ]; then
      die "a recording is paused — resume or stop it first"
    fi
    die "the previous recording ended unexpectedly — stop it to keep what was captured"
  fi

  resolve_target "$label"
  mkdir -p "$TARGET_DIR" || die "cannot create $TARGET_DIR"

  # Checked before the first byte, not after the disk fills: ffmpeg dies mid
  # meeting when it runs out of room, and the segment it was writing goes with
  # it. ~11 MB/hour means this only ever trips on a genuinely full disk.
  local free
  free=$(df -Pm "$TARGET_DIR" 2>/dev/null | awk 'NR==2{print $4}')
  if [ -n "$free" ] && [ "$free" -lt "$MIN_FREE_MB" ]; then
    rmdir "$TARGET_DIR" 2>/dev/null
    die "only ${free} MB free on ${TARGET_DIR} — need ${MIN_FREE_MB} MB"
  fi

  mkdir -p "$STATE_DIR"
  "$JQ" -n --arg dir "$TARGET_DIR" --arg label "$label" --arg ws "$WS_ID" \
    --argjson started "$(date +%s)" \
    '{dir:$dir, label:$label, workspace:$ws, started:$started,
      pausedTotal:0, pausedAt:0}' >"$STATE" || die "cannot write state"

  live_start
  if ! "$SYSTEMCTL" --user start "$UNIT" >/dev/null 2>&1; then
    live_stop
    rm -f "$STATE"; rmdir "$TARGET_DIR" 2>/dev/null
    die "recorder did not start — journalctl --user -u $UNIT"
  fi
  live_window "$TARGET_DIR"

  notify "󰑊 Recording" "${label:-$(basename "$TARGET_DIR")}"
  refresh_bar
  echo "$TARGET_DIR"
}

# Duration of what was actually captured, summed from the segments. Written
# into meta.json so nothing downstream has to probe the audio to know how long
# the meeting was.
parts_duration() { # <dir>
  local total=0 d
  for f in "$1"/part-*.opus; do
    [ -e "$f" ] || continue
    d=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
    total=$(awk -v t="$total" -v d="${d:-0}" 'BEGIN{printf "%.0f", t + d}')
  done
  echo "$total"
}

cmd_stop() {
  [ -f "$STATE" ] || die "not recording"
  local dir label ws started
  dir=$(sget dir); label=$(sget label); ws=$(sget workspace); started=$(sget started)

  "$SYSTEMCTL" --user stop "$UNIT" >/dev/null 2>&1
  live_finish
  live_window_close
  rm -f "$STATE"

  # The glob is quoted so compgen receives the PATTERN. Unquoted, the shell
  # expands it first and compgen matches against only the first path it was
  # handed — which silently reported "1 part" for every recording that had
  # more than one.
  if ! compgen -G "$dir/part-*.opus" >/dev/null 2>&1; then
    rmdir "$dir" 2>/dev/null
    die "no audio was captured — journalctl --user -u $UNIT"
  fi

  local parts duration
  parts=$(compgen -G "$dir/part-*.opus" | wc -l)
  duration=$(parts_duration "$dir")

  "$JQ" -n --arg dir "$dir" --arg label "$label" --arg ws "$ws" \
    --argjson started "${started:-0}" --argjson ended "$(date +%s)" \
    --argjson parts "$parts" --argjson duration "$duration" \
    '{label:$label, workspace:$ws, started:$started, ended:$ended,
      parts:$parts, durationSeconds:$duration}' >"$dir/meta.json"

  mkdir -p "$(dirname "$LAST_FILE")"
  printf '%s\n' "$dir" >"$LAST_FILE"

  notify "Recording saved" "$(human_time "$duration") · $(basename "$dir")"
  refresh_bar

  [ "${AUTO_TRANSCRIBE:-0}" = "1" ] && [ -n "${DEEPGRAM_KEY_FILE:-}" ] && cmd_transcribe "$dir"
  return 0
}

cmd_pause() {
  [ -f "$STATE" ] || die "not recording"
  recording || die "already paused"
  "$SYSTEMCTL" --user stop "$UNIT" >/dev/null 2>&1
  live_finish
  local tmp="$STATE.$$"
  "$JQ" --argjson at "$(date +%s)" '.pausedAt = $at' "$STATE" >"$tmp" && mv -f "$tmp" "$STATE"
  notify "󰏤 Paused" "$(human_time "$(elapsed_now)") recorded"
  refresh_bar
}

cmd_resume() {
  [ -f "$STATE" ] || die "nothing to resume"
  recording && die "already recording"
  local at tmp="$STATE.$$"
  at=$(sget pausedAt)
  # A pause that never happened means the unit died on its own — resuming is
  # still the right move (the segments are intact and numbering continues), so
  # only the accounting differs.
  "$JQ" --argjson now "$(date +%s)" --argjson at "${at:-0}" \
    '.pausedTotal = (.pausedTotal + (if $at > 0 then $now - $at else 0 end)) | .pausedAt = 0' \
    "$STATE" >"$tmp" && mv -f "$tmp" "$STATE"
  live_start
  "$SYSTEMCTL" --user start "$UNIT" >/dev/null 2>&1 || die "could not resume — journalctl --user -u $UNIT"
  notify "󰑊 Recording" "resumed"
  refresh_bar
}

cmd_toggle() {
  if [ -f "$STATE" ]; then
    cmd_stop
  else
    local label=""
    if [ "${1:-}" = "--prompt" ] && [ -n "${FUZZEL:-}" ]; then
      # --lines=0 with no stdin: a free-text field, not a menu. Escape aborts,
      # which must NOT start an unlabelled recording by accident.
      label=$("$FUZZEL" --dmenu --lines=0 --width=40 --prompt="Recording: " \
        --horizontal-pad=8 --vertical-pad=6 --inner-pad=4 \
        --background="$BG" --text-color="$FG" \
        --selection-color="$SEL_BG" --selection-text-color="$SEL_FG" \
        --border-color="$BORDER" --border-width=2 --border-radius=5 \
        --font="$FONT" </dev/null) || exit 0
    fi
    cmd_start "$label"
  fi
}

cmd_pause_toggle() {
  [ -f "$STATE" ] || exit 0
  if recording; then cmd_pause; else cmd_resume; fi
}

# idle | recording | paused | aborted | transcribing
#
# "aborted" is the state that earns this its own function: the unit is gone but
# the state file is not, which means ffmpeg died — suspend, a device that
# vanished, a full disk. The audio up to that point is on disk and `stop`
# finalises it; what must not happen is the bar quietly showing "recording".
cmd_status() {
  local state="idle" dir="" label="" elapsed=0
  if [ -f "$STATE" ]; then
    dir=$(sget dir); label=$(sget label); elapsed=$(elapsed_now)
    if recording; then state="recording"
    elif [ "$(sget pausedAt)" != "0" ]; then state="paused"
    else state="aborted"; fi
  elif [ -f "$TRANSCRIBE_STATE" ]; then
    state="transcribing"
    dir=$("$JQ" -r '.dir // ""' "$TRANSCRIBE_STATE" 2>/dev/null)
  fi

  if [ "${1:-}" = "--json" ]; then
    "$JQ" -nc --arg state "$state" --arg dir "$dir" --arg label "$label" \
      --arg human "$(human_time "$elapsed")" --argjson elapsed "$elapsed" \
      '{state:$state, dir:$dir, label:$label, elapsed:$elapsed, human:$human}'
  else
    case "$state" in
      idle)         echo "idle" ;;
      transcribing) echo "transcribing $(basename "${dir:-?}")" ;;
      *)            echo "$state $(human_time "$elapsed") → $dir" ;;
    esac
  fi
}

cmd_transcribe() {
  local dir="${1:-}"
  [ -z "$dir" ] && dir=$(cat "$LAST_FILE" 2>/dev/null)
  [ -n "$dir" ] && [ -d "$dir" ] || die "no recording to transcribe"
  compgen -G "$dir/part-*.opus" >/dev/null 2>&1 || die "no audio in $dir"
  [ -n "${DEEPGRAM_KEY_FILE:-}" ] \
    || die "transcription is not configured — set features.fluteos.recorder.transcribe.apiKeyFile"

  # Through systemd, for the credential: the key is loaded into a 0400 tmpfs
  # readable only by that unit, so it never becomes an environment variable of
  # this shell or of anything it spawned. A fixed unit name also serialises the
  # work — a second request while one runs fails loudly instead of running two
  # uploads over the same connection.
  "$SYSTEMD_RUN" --user --quiet --collect --unit=fluteos-record-transcribe \
    --description="Transcribe $(basename "$dir")" \
    -p Type=oneshot -p "LoadCredential=deepgram:$DEEPGRAM_KEY_FILE" \
    "$TRANSCRIBE_SCRIPT" "$dir" \
    || die "could not queue transcription — one may already be running"

  notify "Transcribing" "$(basename "$dir")"
  refresh_bar
}

# The window is a view, so it can be closed and asked for again at any point —
# during the meeting, or afterwards over what was said.
cmd_live() {
  local dir=""
  if [ -f "$STATE" ]; then dir=$(sget dir); else dir=$(cat "$LAST_FILE" 2>/dev/null); fi
  [ -n "$dir" ] && [ -d "$dir" ] || die "no recording to show"
  [ -n "${LIVE_WINDOW:-}" ] || die "live transcription is not configured"
  "$SYSTEMD_RUN" --user --quiet --collect --unit=fluteos-record-live-window \
    --description="Live transcript window" \
    "$LIVE_WINDOW" "$dir" >/dev/null 2>&1 \
    || die "the window is already open"
}

cmd_open() {
  local dir="${1:-}"
  [ -z "$dir" ] && dir=$(cat "$LAST_FILE" 2>/dev/null)
  [ -f "$STATE" ] && dir=$(sget dir)
  [ -n "$dir" ] && [ -d "$dir" ] || die "no recording yet"
  "$XDG_OPEN" "$dir" >/dev/null 2>&1 &
}

case "${1:-status}" in
  start)        shift; cmd_start "${1:-}" ;;
  stop)         cmd_stop ;;
  pause)        cmd_pause ;;
  resume)       cmd_resume ;;
  pause-toggle) cmd_pause_toggle ;;
  toggle)       shift; cmd_toggle "${1:-}" ;;
  status)       shift; cmd_status "${1:-}" ;;
  last)         cat "$LAST_FILE" 2>/dev/null || die "nothing recorded yet" ;;
  transcribe)   shift; cmd_transcribe "${1:-}" ;;
  open)         shift; cmd_open "${1:-}" ;;
  live)         cmd_live ;;
  *)            die "usage: fluteos-record start|stop|pause|resume|toggle|status|last|transcribe|open|live" ;;
esac
