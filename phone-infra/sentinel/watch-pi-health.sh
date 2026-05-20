#!/data/data/com.termux/files/usr/bin/bash
# watch-pi-health.sh — Pings the Pi (Anderson hub) and key services.
# Alerts if anything that was healthy goes down.
source ~/sentinel/lib/common.sh

WATCHER=pi-health
PI="anderson-hub.tailf0f27a.ts.net"
STATE_FILE="$STATE_DIR/$WATCHER.json"

# 1. Tailscale reachability to Pi root
ROOT_CODE=$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "https://$PI/")
[ "$ROOT_CODE" = "200" ] && ROOT=up || ROOT=down

# Helper: any HTTP response code 1xx-5xx means the server is alive.
# Only "000" or empty means it failed to reach the service.
is_alive() { [ -n "$1" ] && [ "$1" != "000" ]; }

# 2. Fluxuum API (Pi:3001) — serves under /api/*, root returns 404 (still alive)
FLUX_CODE=$(ssh -o ConnectTimeout=4 -o BatchMode=yes pi 'curl -s -o /dev/null --max-time 3 -w "%{http_code}" http://localhost:3001/' 2>/dev/null)
is_alive "$FLUX_CODE" && FLUX=up || FLUX=down

# 3. FT api (Pi:8080)
FT_CODE=$(ssh -o ConnectTimeout=4 -o BatchMode=yes pi 'curl -s -o /dev/null --max-time 3 -w "%{http_code}" http://localhost:8080/' 2>/dev/null)
is_alive "$FT_CODE" && FT=up || FT=down

# Compose state
CURR="root=$ROOT flux=$FLUX ft=$FT"
PREV=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# Only alert if any service is down AND state changed (or no prev state)
if [ "$ROOT" = "down" ]; then
  alert_throttled "pi-root-down" "critical" "Pi unreachable" "Anderson hub not responding via Tailscale."
fi
if [ "$FLUX" = "down" ] && [ "$ROOT" = "up" ]; then
  alert_throttled "pi-flux-down" "warn" "Fluxuum API down" "Pi reachable but :3001 not responding."
fi
if [ "$FT" = "down" ] && [ "$ROOT" = "up" ]; then
  alert_throttled "pi-ft-down" "warn" "Facility Tracker down" "Pi reachable but :8080 not responding."
fi

# Recovery: log when all-up returns after a down period
if [ "$CURR" = "root=up flux=up ft=up" ] && [ "$PREV" != "$CURR" ] && [ -n "$PREV" ]; then
  log_digest info "$WATCHER" "all services back: $PREV -> $CURR"
fi

echo "$CURR" > "$STATE_FILE"
