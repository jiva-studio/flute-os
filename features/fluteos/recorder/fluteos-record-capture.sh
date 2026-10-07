#!/usr/bin/env bash
# The recording itself: everything you can hear, into segmented Opus.
#
# Run by fluteos-record.service, never by hand — the target directory comes from
# the state file fluteos-record writes, so starting this on its own records into
# whatever the last session left behind.
#
# Both halves of a meeting are captured: the default sink's MONITOR (the other
# people) and the default source (you), mixed into one mono track. One file with
# everybody in it is what a transcriber wants; keeping them apart would only pay
# off if we diarised locally, and Deepgram already labels speakers.
#
# Dependencies: JQ FFMPEG WPCTL NOTIFY_SEND SEGMENT_SECONDS SAMPLE_RATE BITRATE
#   LIVE_ENABLED MIC_GAIN_DB SYSTEM_GAIN_DB LEVELLING
#   (via environment)

set -u

STATE="${XDG_RUNTIME_DIR:-/tmp}/fluteos-record/state.json"

fail() {
  echo "$1" >&2
  [ -n "${NOTIFY_SEND:-}" ] && "$NOTIFY_SEND" -u critical "Recorder" "$1" >/dev/null 2>&1
  exit 1
}

[ -f "$STATE" ] || fail "no recording is armed (missing state file)"
DIR=$("$JQ" -r '.dir // ""' "$STATE" 2>/dev/null)
[ -n "$DIR" ] && [ -d "$DIR" ] || fail "recording directory is gone"

# --- devices ----------------------------------------------------------------
#
# Resolved here rather than baked in: which sink is "the speakers" changes when
# headphones are plugged in, and the answer has to be right at the moment the
# meeting starts, not at the moment the system was built.
#
# Resolved at the moment the capture STARTS, and not revisited: ffmpeg holds the
# stream it opened. Plugging in headphones mid-meeting therefore keeps recording
# the old device — which is also why `pause` + `resume` re-runs this script, and
# is the way to follow a device change without losing what came before.
#
# node.name, not node.description — the description is a human label ("Ryzen HD
# Audio Controller Speaker") and PulseAudio addresses devices by name.
node_name() { # <wpctl target>
  "$WPCTL" inspect "$1" 2>/dev/null \
    | sed -n 's/^[[:space:]]*\*\?[[:space:]]*node\.name = "\(.*\)"$/\1/p' \
    | head -1
}

SINK=$(node_name @DEFAULT_AUDIO_SINK@)
MIC=$(node_name @DEFAULT_AUDIO_SOURCE@)
MON=""
[ -n "$SINK" ] && MON="$SINK.monitor"

# A default source that IS a monitor (some docks, some virtual sinks) would be
# mixed with itself — everything twice, and the mic nowhere.
case "$MIC" in *.monitor) [ "$MIC" = "$MON" ] && MIC="" ;; esac
[ -n "$MON" ] || [ -n "$MIC" ] || fail "no audio devices — nothing to record"

# --- where to continue ------------------------------------------------------
#
# Segments are numbered from the files already on disk, so resuming after a
# pause appends instead of overwriting part-000. `ls | wc -l` is enough: the
# numbering only has to be monotonic and collision-free, not gapless.
NEXT=0
for f in "$DIR"/part-*.opus; do [ -e "$f" ] && NEXT=$((NEXT + 1)); done

# --- capture ----------------------------------------------------------------
#
# aresample=async=1 on each input before the mix, because the sink and the
# microphone are driven by two independent clocks. Without it ffmpeg reports
# non-monotonic DTS within seconds and the drift accumulates across a meeting;
# with it, each input is resampled onto the output timeline.
#
# normalize=0, because amix otherwise divides every input by the number of
# inputs — a meeting recorded at half volume, which costs more in transcription
# accuracy than the rare clip it avoids.
#
# 16 kHz mono Opus at 24 kbit/s: what speech recognition actually consumes
# (~11 MB per hour), not an archival master.
# The two sources arrive at whatever level their own device gives, and they are
# summed as they are (normalize=0). That is deliberate for the sum — halving
# everything to avoid a rare clip costs more transcription accuracy than it buys
# — but it means nothing balances the two against each other: a laptop
# microphone with automatic gain sits far hotter than a meeting playing at a
# third of the system volume, and the person wearing the microphone comes out
# loudest in their own recording.
#
# A fixed gain per side cannot fix this on its own, and that is worth being
# clear about: it balances the microphone against the meeting, but inside the
# meeting the participants are still at whatever level their own microphones
# and connections give — one person twice as loud as the next, on the same
# input. A single number cannot follow that.
#
# So each input is LEVELLED as it plays, and the fixed gain remains for the
# coarse offset between the two sides. `speechnorm` is the filter for it: it
# works a phrase at a time towards a target peak, expanding what is quiet and
# compressing what is loud, and is built for speech rather than for music.
#
# Measured on a real meeting, five minutes of it:
#
#   as recorded            loudness range 18.2 LU, peak +0.2 dBFS
#   speechnorm             loudness range 10.6 LU, peak  0.0 dBFS
#   speechnorm + limiter   loudness range 10.6 LU, peak -0.6 dBFS
#
# The spread between the loudest and the quietest voice is roughly halved. The
# peak is the other half of the finding: the mix was CLIPPING, so the limiter
# after it is not belt-and-braces, it is fixing something that was happening.
#
# No threshold (`t`, default 0): with t=0.02 the quiet speech never got expanded
# and the range came out at 19.3 LU — worse than doing nothing.
LEVEL=""
LIMIT=""
if [ "${LEVELLING:-speechnorm}" = "speechnorm" ]; then
  LEVEL=",speechnorm=p=0.95:e=8:c=2:r=0.0005:f=0.001:l=1"
  LIMIT=",alimiter=limit=0.89:level=false"
fi

if [ -n "$MON" ] && [ -n "$MIC" ]; then
  INPUTS=(-f pulse -name fluteos-record-system -i "$MON"
          -f pulse -name fluteos-record-mic -i "$MIC")
  FILTER="[0:a]aresample=async=1:first_pts=0,volume=${SYSTEM_GAIN_DB:-0}dB$LEVEL[s]"
  FILTER="$FILTER;[1:a]aresample=async=1:first_pts=0,volume=${MIC_GAIN_DB:-0}dB$LEVEL[m]"
  FILTER="$FILTER;[s][m]amix=inputs=2:duration=longest:normalize=0$LIMIT[a]"
else
  ONLY="${MON:-$MIC}"
  INPUTS=(-f pulse -name fluteos-record -i "$ONLY")
  FILTER="[0:a]aresample=async=1:first_pts=0$LEVEL$LIMIT[a]"
  echo "only one source available ($ONLY) — recording it alone" >&2
fi

# --- the live tap -----------------------------------------------------------
#
# A second output of the same mix, raw, for whoever is transcribing it as it
# happens. Two decisions here, and both were made by measuring what happens
# when the listener dies mid-meeting:
#
#   * the `fifo` muxer, which hands the write to its own thread and DROPS what
#     it cannot deliver instead of stalling the encoder;
#   * a unix SOCKET rather than a named pipe. Connecting to a socket nobody is
#     listening on is refused immediately; opening a FIFO for writing blocks
#     until a reader appears. With a pipe, a dead listener left ffmpeg unable
#     to finish at all — it kept recording, but would not exit, and the stop
#     that followed truncated the last segment. With a socket it retries, is
#     refused, and the meeting ends cleanly.
#
# Recovery is deliberately unlimited: exhausting the attempts ends the whole
# ffmpeg run, segments included, which was the one outcome worth avoiding.
# A filter output feeds exactly one -map, so the mix is SPLIT rather than
# mapped twice: ffmpeg refuses the second use with "label does not exist in any
# defined filter graph, or was already used elsewhere" and opens no output at
# all — a recording that fails to start rather than one that misses its tap.
LIVE_SOCKET="$(dirname "$STATE")/live.sock"
LIVE_OUT=()
SEGMENT_LABEL="[a]"
if [ "${LIVE_ENABLED:-0}" = "1" ] && [ -S "$LIVE_SOCKET" ]; then
  FILTER="$FILTER;[a]asplit=2[seg][live]"
  SEGMENT_LABEL="[seg]"
  LIVE_OUT=(-map "[live]" -ac 1 -ar "$SAMPLE_RATE" -c:a pcm_s16le
            -f fifo -fifo_format s16le
            -queue_size 200 -drop_pkts_on_overflow 1
            -attempt_recovery 1 -recovery_wait_time 1
            "unix://$LIVE_SOCKET")
fi

# exec: ffmpeg becomes the unit's main process, so the SIGINT that
# fluteos-record sends on stop reaches the encoder itself and it finalises the
# open segment. A wrapper in between would swallow it and truncate the file.
exec "$FFMPEG" -hide_banner -loglevel warning -nostdin \
  "${INPUTS[@]}" \
  -filter_complex "$FILTER" \
  "${LIVE_OUT[@]}" \
  -map "$SEGMENT_LABEL" -ac 1 -ar "$SAMPLE_RATE" -c:a libopus -b:a "$BITRATE" \
  -f segment -segment_time "$SEGMENT_SECONDS" -reset_timestamps 1 \
  -segment_start_number "$NEXT" \
  "$DIR/part-%03d.opus"
