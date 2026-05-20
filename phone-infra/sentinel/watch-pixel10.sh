#!/data/data/com.termux/files/usr/bin/bash
# watch-pixel10.sh — Watches the heartbeat stream for Pixel 10.
# If Pixel 10 hasn't pinged in >12 minutes (should be every 5), alert.
source ~/sentinel/lib/common.sh

WATCHER=pixel10-watchdog

# Pull recent heartbeats from ntfy and find latest Pixel 10 timestamp
LATEST=$(curl -s --max-time 6 "https://ntfy.sh/$NTFY_TOPIC/json?poll=1&since=30m" 2>/dev/null \
  | python3 -c "
import sys, json
latest = 0
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if 'Pixel 10' in d.get('title','') or 'Pixel 10' in d.get('message',''):
            latest = max(latest, d.get('time', 0))
    except: pass
print(latest)
" 2>/dev/null)

NOW=$(now_epoch)
AGE=$((NOW - LATEST))

if [ "$LATEST" = "0" ]; then
  alert_throttled "p10-no-heartbeat" "warn" "Pixel 10 silent" "No Pixel 10 heartbeats in the last 30 minutes."
elif [ "$AGE" -gt 720 ]; then
  alert_throttled "p10-stale" "warn" "Pixel 10 stale" "Last Pixel 10 ping was ${AGE} seconds ago. Expected every 300 seconds."
fi
