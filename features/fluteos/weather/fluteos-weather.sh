#!/usr/bin/env bash
# Weather widget for Waybar using Open-Meteo API
# Dependencies: CURL, JQ (set via environment)

# Weather code to icon mapping (WMO codes) with Pango markup
get_icon() {
  case $1 in
    0) echo "<span size='16pt' rise='-2pt'>󰖙</span>" ;;          # Clear sky
    1|2|3) echo "<span size='16pt' rise='-2pt'>󰖐</span>" ;;      # Partly cloudy
    45|48) echo "<span size='16pt' rise='-2pt'>󰖑</span>" ;;      # Fog
    51|53|55) echo "<span size='16pt' rise='-2pt'>󰖗</span>" ;;   # Drizzle
    61|63|65) echo "<span size='16pt' rise='-2pt'>󰖖</span>" ;;   # Rain
    66|67) echo "<span size='16pt' rise='-2pt'>󰖒</span>" ;;      # Freezing rain
    71|73|75) echo "<span size='16pt' rise='-2pt'>󰖘</span>" ;;   # Snow
    77) echo "<span size='16pt' rise='-2pt'>󰖘</span>" ;;         # Snow grains
    80|81|82) echo "<span size='16pt' rise='-2pt'>󰖖</span>" ;;   # Rain showers
    85|86) echo "<span size='16pt' rise='-2pt'>󰖘</span>" ;;      # Snow showers
    95|96|99) echo "<span size='16pt' rise='-2pt'>󰖓</span>" ;;   # Thunderstorm
    *) echo "<span size='16pt' rise='-2pt'>󰖐</span>" ;;
  esac
}

# Get location from IP
LOCATION=$("$CURL" -sf --connect-timeout 5 'http://ip-api.com/json/?fields=lat,lon' 2>/dev/null)
if [ -z "$LOCATION" ]; then
  echo "<span size='16pt' rise='-2pt'>󰖐</span> --"
  exit 0
fi

LAT=$(echo "$LOCATION" | "$JQ" -r '.lat')
LON=$(echo "$LOCATION" | "$JQ" -r '.lon')

# Get weather
WEATHER=$("$CURL" -sf --connect-timeout 5 "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,weather_code" 2>/dev/null)
if [ -z "$WEATHER" ]; then
  echo "<span size='16pt' rise='-2pt'>󰖐</span> --"
  exit 0
fi

TEMP=$(echo "$WEATHER" | "$JQ" -r '.current.temperature_2m' | cut -d. -f1)
CODE=$(echo "$WEATHER" | "$JQ" -r '.current.weather_code')
ICON=$(get_icon "$CODE")

echo "$ICON $TEMP°"
