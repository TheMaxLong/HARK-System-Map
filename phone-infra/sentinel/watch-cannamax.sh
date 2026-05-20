#!/data/data/com.termux/files/usr/bin/bash
# watch-cannamax.sh — Polls CannaMax drift detector for new drift events.
# Alerts on each new drift signature not previously seen.
#
# Auto-parks when no URL is configured. To enable:
#   echo "https://your-cannamax-host/api/change-events?since=15m" > ~/sentinel/cannamax.url
# When the file is missing or empty, this script exits silently (no digest noise).
source ~/sentinel/lib/common.sh

WATCHER=cannamax-drift
URL_FILE="$HOME/sentinel/cannamax.url"

# Self-park if no URL configured — avoid spamming digest until CannaMax is deployed.
if [[ ! -s "$URL_FILE" ]]; then
  exit 0
fi
PRIMARY_URL=$(head -1 "$URL_FILE" | tr -d '[:space:]')
[[ -z "$PRIMARY_URL" ]] && exit 0

ENDPOINTS=("$PRIMARY_URL")
SEEN_FILE="$STATE_DIR/$WATCHER.seen"
touch "$SEEN_FILE"

DRIFT_JSON=""
for url in "${ENDPOINTS[@]}"; do
  RESP=$(curl -s --max-time 5 "$url" 2>/dev/null)
  if echo "$RESP" | python3 -c "import sys,json;json.loads(sys.stdin.read())" 2>/dev/null; then
    DRIFT_JSON="$RESP"; ENDPOINT_OK="$url"; break
  fi
done

if [ -z "$DRIFT_JSON" ]; then
  # All endpoints failed — log once per throttle window (don't spam)
  alert_throttled "cannamax-endpoint-unreachable" "info" "CannaMax silent" "No drift endpoint responding — verify URL or service is up."
  exit 0
fi

NEW_EVENTS=$(echo "$DRIFT_JSON" | python3 - <<PYEOF
import sys, json
try:
    data = json.load(sys.stdin)
    events = data if isinstance(data, list) else data.get("events", data.get("drifts", []))
    for e in events:
        if not isinstance(e, dict): continue
        sig = e.get("id") or f"{e.get('room','?')}|{e.get('zone','?')}|{e.get('timestamp','?')}"
        room = e.get("room", e.get("zone","?"))
        kind = e.get("kind", e.get("type", "drift"))
        delta = e.get("delta", e.get("value",""))
        print(f"{sig}\t{room}\t{kind}\t{delta}")
except Exception:
    pass
PYEOF
)

while IFS=$'\t' read -r SIG ROOM KIND DELTA; do
  [ -z "$SIG" ] && continue
  if ! grep -qxF "$SIG" "$SEEN_FILE"; then
    echo "$SIG" >> "$SEEN_FILE"
    alert_throttled "cannamax-$SIG" "warn" "Drift on $ROOM" "$KIND $DELTA"
  fi
done <<< "$NEW_EVENTS"

# Trim seen-file to last 500 entries
tail -500 "$SEEN_FILE" > "$SEEN_FILE.tmp" && mv "$SEEN_FILE.tmp" "$SEEN_FILE"
