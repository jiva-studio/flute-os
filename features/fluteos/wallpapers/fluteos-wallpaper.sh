# Wallpaper rotation script using awww for animated transitions.
# Modes: --next (cycle once), --random (random once), default (daemon loop).
# Optional --category|-c <subdir> restricts to $WALLPAPER_DIR/<subdir>.
WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"
STATE_FILE="${HOME}/.local/share/wallpapers/.current-wallpaper"

mkdir -p "$(dirname "$STATE_FILE")"

CATEGORY=""
ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --next) ACTION="next"; shift ;;
    --random) ACTION="random"; shift ;;
    # `shift 2` with only one argument left fails AND does not shift, so the
    # loop condition never changes: `fluteos-wallpaper -c` used to spin forever.
    --category|-c)
      if [ $# -lt 2 ]; then
        echo "fluteos-wallpaper: $1 needs a category name" >&2
        exit 2
      fi
      CATEGORY="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$ACTION" ] && ACTION="daemon"

# Block until awww-daemon socket is ready (service starts in parallel)
for _ in $(seq 1 50); do
  "$AWWW" query >/dev/null 2>&1 && break
  sleep 0.1
done

get_wallpapers() {
  local search_dir="$WALLPAPER_DIR"
  if [ -n "$CATEGORY" ] && [ -d "$WALLPAPER_DIR/$CATEGORY" ]; then
    search_dir="$WALLPAPER_DIR/$CATEGORY"
  fi
  find -L "$search_dir" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" \) | sort
}

get_next_wallpaper() {
  local walls
  # mapfile, not `walls=($(...))`: word splitting turned "Blue Sky.png" into two
  # entries, so awww was handed "Blue" and the state file recorded a path that
  # does not exist — after which --next could never advance past it.
  mapfile -t walls < <(get_wallpapers)
  local count=${#walls[@]}

  if [ "$count" -eq 0 ]; then
    echo ""
    return
  fi

  local current=""
  if [ -f "$STATE_FILE" ]; then
    current=$(cat "$STATE_FILE")
  fi

  local next_index=0
  if [ -n "$current" ]; then
    for i in "${!walls[@]}"; do
      if [ "${walls[$i]}" = "$current" ]; then
        next_index=$(( (i + 1) % count ))
        break
      fi
    done
  fi

  echo "${walls[$next_index]}"
}

set_wallpaper() {
  local wp="$1"
  if [ -n "$wp" ]; then
    echo "$(date): Setting wallpaper: $wp"
    echo "$wp" > "$STATE_FILE"
    "$AWWW" img "$wp" \
      --transition-type fade \
      --transition-duration 1.5 \
      --transition-fps 60
  fi
}

if [ "$ACTION" = "next" ]; then
  set_wallpaper "$(get_next_wallpaper)"
  exit 0
fi

if [ "$ACTION" = "random" ]; then
  mapfile -t walls_random < <(get_wallpapers)
  count_random=${#walls_random[@]}
  # An empty wallpaper directory made this a division by zero.
  if [ "$count_random" -eq 0 ]; then
    echo "fluteos-wallpaper: no wallpapers found under $WALLPAPER_DIR${CATEGORY:+/$CATEGORY}" >&2
    exit 1
  fi
  random_index=$(( RANDOM % count_random ))
  set_wallpaper "${walls_random[$random_index]}"
  exit 0
fi

if [ "$ACTION" = "daemon" ]; then
  while true; do
    set_wallpaper "$(get_next_wallpaper)"
    sleep "$INTERVAL"
  done
fi
