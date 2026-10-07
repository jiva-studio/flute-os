#!/usr/bin/env bash
# Turn a recording's segments into a transcript.
#
#   fluteos-record-transcribe <recording-dir>
#
# Run as a systemd unit by `fluteos-record transcribe`, which is also how the
# API key gets here: as a systemd credential, never as an environment variable.
#
# Segment-at-a-time, and RESUMABLE: a part whose JSON is already on disk is
# skipped, so a run that died halfway through a three-hour meeting — network
# down, laptop closed — is fixed by running it again rather than by re-uploading
# and re-paying for everything. That is also what makes this safe to point at an
# old recording months later.
#
# Dependencies: JQ CURL FFPROBE NOTIFY_SEND PKILL ENDPOINT MODEL LANGUAGE
#   (via environment)

set -u

DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: fluteos-record-transcribe <dir>" >&2; exit 1; }

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/fluteos-record"
MARKER="$STATE_DIR/transcribing.json"
BAR_SIGNAL=14

notify() { [ -n "${NOTIFY_SEND:-}" ] && "$NOTIFY_SEND" "$@" >/dev/null 2>&1; return 0; }
refresh_bar() { "$PKILL" -SIGRTMIN+"$BAR_SIGNAL" waybar >/dev/null 2>&1; return 0; }
fail() { echo "$1" >&2; notify -u critical "Transcription failed" "$1"; exit 1; }

# The marker is what the bar reads to show "transcribing". It is removed on
# every exit path, including a kill — a stale marker would leave the chip
# claiming work that is not happening.
mkdir -p "$STATE_DIR"
cleanup() { rm -f "$MARKER"; refresh_bar; }
trap cleanup EXIT INT TERM
"$JQ" -n --arg dir "$DIR" --argjson started "$(date +%s)" \
  '{dir:$dir, started:$started}' >"$MARKER"
refresh_bar

KEY=""
[ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -r "$CREDENTIALS_DIRECTORY/deepgram" ] \
  && KEY=$(cat "$CREDENTIALS_DIRECTORY/deepgram")
[ -n "$KEY" ] || fail "no API key — check features.fluteos.recorder.transcribe.apiKeyFile"

mkdir -p "$DIR/parts"

# Query options, in one place:
#   smart_format  punctuation, capitalisation, numbers as digits
#   diarize       "who said this" — the whole point for a meeting
#   utterances    speech grouped into turns instead of a wall of words
URL="$ENDPOINT?model=$MODEL&language=$LANGUAGE&smart_format=true&punctuate=true&diarize=true&utterances=true"

OFFSET=0        # seconds of audio before the current segment
FAILED=0
DONE=0
for f in "$DIR"/part-*.opus; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .opus)
  out="$DIR/parts/$base.json"

  dur=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
  dur="${dur:-0}"

  # The segment muxer leaves a fraction-of-a-second tail behind when a recording
  # stops on a segment boundary. Uploading it costs a request and returns
  # nothing.
  if awk -v d="$dur" 'BEGIN{exit !(d < 0.5)}'; then
    OFFSET=$(awk -v o="$OFFSET" -v d="$dur" 'BEGIN{printf "%.3f", o + d}')
    continue
  fi

  if [ ! -s "$out" ]; then
    code=$("$CURL" -sS -X POST "$URL" \
      -H "Authorization: Token $KEY" \
      -H "Content-Type: audio/ogg" \
      --data-binary "@$f" \
      --retry 2 --retry-delay 10 --retry-connrefused \
      --max-time 900 \
      -o "$out.tmp" -w '%{http_code}' 2>"$out.err")
    if [ "$code" != "200" ]; then
      # Keep the body: Deepgram says WHY in it (bad key, unknown model, quota),
      # and a bare "it failed" would send you to the wrong place.
      echo "$base: HTTP ${code:-?} — $(head -c 300 "$out.tmp" 2>/dev/null)" >&2
      rm -f "$out.tmp"
      FAILED=$((FAILED + 1))
      OFFSET=$(awk -v o="$OFFSET" -v d="$dur" 'BEGIN{printf "%.3f", o + d}')
      continue
    fi
    rm -f "$out.err"
    mv -f "$out.tmp" "$out"
  fi

  # The offset each part starts at, stored WITH the part: rebuilding the
  # transcript later must not depend on re-probing every file in order.
  tmp="$out.$$"
  "$JQ" --argjson off "$OFFSET" '. + {fluteosOffset: $off}' "$out" >"$tmp" && mv -f "$tmp" "$out"

  DONE=$((DONE + 1))
  OFFSET=$(awk -v o="$OFFSET" -v d="$dur" 'BEGIN{printf "%.3f", o + d}')
done

compgen -G "$DIR/parts/part-*.json" >/dev/null 2>&1 \
  || fail "nothing was transcribed ($FAILED segment(s) failed)"

# --- merge ------------------------------------------------------------------
#
# One flat list of turns with absolute timestamps. Consecutive turns by the same
# speaker are joined: Deepgram splits on sentences, and a page of one-line
# paragraphs is unreadable for exactly the thing this is for — skimming an hour
# you sat through.
#
# Speaker numbers are assigned PER REQUEST, so "Speaker 0" in the second
# segment is not necessarily "Speaker 0" in the first. Nothing here can fix
# that — the segments are diarised independently, which is the price of a
# transcription pass that survives a dropped connection — so the transcript
# says so rather than letting the numbers be read as identities.
"$JQ" -s '
  [ .[]
    | (.fluteosOffset // 0) as $off
    | ( .results.utterances //
        [ { start: 0, end: 0, speaker: 0,
            transcript: (.results.channels[0].alternatives[0].transcript // "") } ] )
    | .[]
    | select((.transcript // "") != "")
    | { start: (.start + $off), end: (.end + $off),
        speaker: (.speaker // 0), text: .transcript }
  ]
  | sort_by(.start)
  | reduce .[] as $u ([];
      if (length > 0) and (.[-1].speaker == $u.speaker)
      then .[:-1] + [ .[-1] + { end: $u.end, text: (.[-1].text + " " + $u.text) } ]
      else . + [$u] end)
' "$DIR"/parts/part-*.json >"$DIR/transcript.json" || fail "could not merge segments"

META="$DIR/meta.json"
[ -f "$META" ] || echo '{}' >"$META"

"$JQ" -r --slurpfile meta "$META" --arg dir "$(basename "$DIR")" --argjson failed "$FAILED" '
  def hhmmss: (. // 0) | floor
    | "\(. / 3600 | floor | tostring | if length < 2 then "0" + . else . end):" +
      "\((. % 3600) / 60 | floor | tostring | if length < 2 then "0" + . else . end):" +
      "\(. % 60 | tostring | if length < 2 then "0" + . else . end)";

  ($meta[0] // {}) as $m
  | "# " + (if ($m.label // "") != "" then $m.label else $dir end),
    "",
    ("- Recorded: " + (($m.started // 0) | strftime("%Y-%m-%d %H:%M"))),
    ("- Duration: " + (($m.durationSeconds // 0) | hhmmss)),
    ("- Workspace: " + (($m.workspace // "—"))),
    (if $failed > 0 then "- **\($failed) segment(s) failed to transcribe — rerun `fluteos-record transcribe`**" else empty end),
    (if (($m.parts // 1) > 1)
     then "- Speaker numbers restart with each segment — the same person may be Speaker 0 early on and Speaker 1 later"
     else empty end),
    "",
    "## Transcript",
    "",
    ( .[] | "**[\(.start | hhmmss)] Speaker \(.speaker)**\n\n\(.text)\n" )
' "$DIR/transcript.json" >"$DIR/transcript.md" || fail "could not write transcript.md"

if [ "$FAILED" -gt 0 ]; then
  notify -u critical "Transcript incomplete" "$FAILED of $((DONE + FAILED)) segments failed — rerun to finish"
else
  notify "Transcript ready" "$(basename "$DIR")/transcript.md"
fi
