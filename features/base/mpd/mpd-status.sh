#!/usr/bin/env bash
# MPD status script for waybar
# Dependencies: MPC (set via environment)

status=$("$MPC" status 2>/dev/null)

if [ -z "$status" ]; then
  echo '{"text": "<span size='"'"'16pt'"'"' rise='"'"'-3pt'"'"'>󰎊</span>"}'
  exit 0
fi

state=$(echo "$status" | grep -oP '\[(\w+)\]' | tr -d '[]')

if [ -z "$state" ]; then
  echo '{"text": "<span size='"'"'16pt'"'"' rise='"'"'-3pt'"'"'>󰎊</span>"}'
  exit 0
fi

# Get title, artist, and filename
title=$("$MPC" current -f "%title%")
artist=$("$MPC" current -f "%artist%")
filename=$("$MPC" current -f "%file%" | sed 's/\.[^.]*$//' | sed 's/.*\///')

# Use title if available, otherwise filename
if [ -n "$title" ]; then
  display="$title"
  [ -n "$artist" ] && display="$title - $artist"
else
  display="$filename"
fi

# Truncate if too long
if [ ${#display} -gt 40 ]; then
  display="${display:0:37}..."
fi

# Escape for JSON
display=$(echo "$display" | sed 's/"/\\"/g')

if [ "$state" = "paused" ]; then
  echo "{\"text\": \"<span size='16pt' rise='-3pt'>󰏤</span> $display\", \"class\": \"paused\"}"
else
  echo "{\"text\": \"<span size='16pt' rise='-3pt'>󰎆</span> $display\", \"class\": \"playing\"}"
fi
