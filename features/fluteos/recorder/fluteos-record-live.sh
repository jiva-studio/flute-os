#!/usr/bin/env bash
# Entry point of fluteos-record-live.service: work out which meeting is being
# recorded, then become the streaming client listening for its audio.
#
# The socket is created by the client, and this unit is started BEFORE the
# capture unit, so ffmpeg has something to connect to by the time it starts.
# Should it start first anyway, it is refused and retries — which is the whole
# reason this is a socket and not a pipe.
#
# Dependencies: JQ PYTHON LIVE_SCRIPT ENDPOINT MODEL LANGUAGE SAMPLE_RATE
#   (via environment)

set -u

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/fluteos-record"
STATE="$STATE_DIR/state.json"
SOCKET="$STATE_DIR/live.sock"

[ -f "$STATE" ] || { echo "no recording is armed (missing state file)" >&2; exit 1; }
DIR=$("$JQ" -r '.dir // ""' "$STATE" 2>/dev/null)
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "recording directory is gone" >&2; exit 1; }

mkdir -p "$STATE_DIR"

exec "$PYTHON" "$LIVE_SCRIPT" "$DIR" "$SOCKET"
