#!/usr/bin/env bash
# Widget on-click: pick a tailnet from a fuzzel menu and (re-)log its userspace
# daemon in. ALWAYS-UP model — this does NOT switch; it just authenticates a
# daemon that is down / NeedsLogin. The actual `tailscale up` runs in a wezterm
# window so the auth URL is visible and clickable.
#
# Env: JQ, TAILSCALE, FUZZEL, WEZTERM, NOTIFY_SEND, LOGIN (login bin), NETS,
#      BG/FG/SEL_BG/SEL_FG/BORDER/FONT (theme).
set -u

[ -f "$NETS" ] || exit 0
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Build menu lines "<icon> <disp> — <state>" and a parallel list of names.
mapfile -t names < <("$JQ" -r '.[].name' "$NETS")
[ "${#names[@]}" -gt 0 ] || exit 0

labels=""
while read -r row; do
  icon="$("$JQ" -r '.icon' <<<"$row")"
  disp="$("$JQ" -r '.disp' <<<"$row")"
  sock="$("$JQ" -r '.sock' <<<"$row")"
  state="$("$TAILSCALE" --socket="$RT/$sock" status --json 2>/dev/null | "$JQ" -r '.BackendState // "Down"' 2>/dev/null)"
  [ "$state" = "Running" ] && mark="✓" || mark="✗"
  labels="$labels$icon $disp — $mark ${state:-Down}"$'\n'
done < <("$JQ" -c '.[]' "$NETS")

idx="$(printf '%s' "$labels" | "$FUZZEL" --dmenu --index \
  --prompt="tailnet login: " --width=34 \
  --background="$BG" --text-color="$FG" \
  --selection-color="$SEL_BG" --selection-text-color="$SEL_FG" \
  --border-color="$BORDER" --border-width=2 --border-radius=5 \
  --font="$FONT")" || exit 0

[ -n "$idx" ] || exit 0
name="${names[$idx]}"
[ -n "$name" ] || exit 0

# Run the login in a terminal so the user can see/click the auth URL.
"$WEZTERM" start --class fluteos-tailnet-login -- \
  bash -lc "$LOGIN '$name'; echo; echo '[press enter to close]'; read -r" \
  2>/dev/null \
  || "$NOTIFY_SEND" -h string:x-canonical-private-synchronous:tailnet \
       "Tailnet" "Run: fluteos-tailnet-login $name" 2>/dev/null || true
