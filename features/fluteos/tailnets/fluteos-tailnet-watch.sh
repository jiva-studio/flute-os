#!/usr/bin/env bash
# Waybar custom module (return-type=json), POLLED via `interval`. One-shot:
# reports how many tailnets are connected and which. ALWAYS-UP model — there is
# no switching; every tailnet has its own userspace tailscaled. For each net we
# ask its private socket for BackendState (== "Running" → connected).
#
# text:    one glyph per tailnet, in order — its icon if connected, else ✗
#          e.g. "🪷 🏠" (both up) / "✗ 🏠" (jiva down) / "✗ ✗" (none)
# class:   active (all up) | partial (some up) | down (none up)
# tooltip: per-net ✓/✗ lines. Click → fluteos-tailnet-menu (login picker).
#
# Env: JQ, TAILSCALE, NETS (path to tailnets-widget.json)
set -u

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

[ -n "${NETS:-}" ] && [ -f "$NETS" ] || { printf '{"text":"","tooltip":"no tailnets configured","class":"down"}\n'; exit 0; }

mapfile -t rows < <("$JQ" -c '.[]' "$NETS" 2>/dev/null)
total=${#rows[@]}
[ "$total" -gt 0 ] || { printf '{"text":"","tooltip":"no tailnets configured","class":"down"}\n'; exit 0; }

up=0
glyphs=""
tip="Tailnets ($total):"
for row in "${rows[@]}"; do
  icon="$("$JQ" -r '.icon' <<<"$row")"
  disp="$("$JQ" -r '.disp' <<<"$row")"
  sock="$("$JQ" -r '.sock' <<<"$row")"
  state="$("$TAILSCALE" --socket="$RT/$sock" status --json 2>/dev/null | "$JQ" -r '.BackendState // "Down"' 2>/dev/null)"
  if [ "$state" = "Running" ]; then
    up=$((up + 1))
    glyphs="$glyphs${glyphs:+ }$icon"
    tip="$tip\n  $icon $disp — ✓ connected"
  else
    glyphs="$glyphs${glyphs:+ }✗"
    tip="$tip\n  $icon $disp — ✗ ${state:-down}"
  fi
done

if [ "$up" -eq 0 ]; then
  class="down"
elif [ "$up" -eq "$total" ]; then
  class="active"
else
  class="partial"
fi

printf '{"text":"%s","tooltip":"%s\\n(click to log in)","class":"%s"}\n' "$glyphs" "$tip" "$class"
