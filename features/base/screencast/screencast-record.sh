pidfile="/tmp/wf-recorder.pid"
outdir="$HOME/Videos/Screencasts"
case "$1" in
  screen)
    if [ -f "$pidfile" ]; then notify-send "Screencast" "Already recording"; exit 1; fi
    mkdir -p "$outdir"
    filename="$outdir/Screencast-$(date +%Y-%m-%d_%H-%M-%S).mp4"
    output=$(niri msg focused-output | head -1 | grep -oP '\(([^)]+)\)' | tr -d '()')
    nohup wf-recorder -a -o "$output" -f "$filename" >/dev/null 2>&1 &
    echo $! > "$pidfile"
    notify-send "Screencast" "Recording started"
    ;;
  region)
    if [ -f "$pidfile" ]; then notify-send "Screencast" "Already recording"; exit 1; fi
    mkdir -p "$outdir"
    filename="$outdir/Screencast-$(date +%Y-%m-%d_%H-%M-%S).mp4"
    geometry=$(slurp)
    if [ -n "$geometry" ]; then
      nohup wf-recorder -a -g "$geometry" -f "$filename" >/dev/null 2>&1 &
      echo $! > "$pidfile"
      notify-send "Screencast" "Recording started"
    fi
    ;;
  stop)
    if [ -f "$pidfile" ]; then
      kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
      notify-send "Screencast" "Recording saved"
    else notify-send "Screencast" "Not recording"; fi
    ;;
  *) echo "Usage: screencast-record screen|region|stop"; exit 1 ;;
esac
