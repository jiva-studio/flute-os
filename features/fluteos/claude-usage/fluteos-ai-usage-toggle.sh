STATE_FILE="$HOME/.cache/ai-usage/mode"
mkdir -p "$(dirname "$STATE_FILE")"

CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "claude")

if [ "$CURRENT" = "claude" ]; then
  echo "openrouter" > "$STATE_FILE"
else
  echo "claude" > "$STATE_FILE"
fi

pkill -SIGRTMIN+13 waybar
