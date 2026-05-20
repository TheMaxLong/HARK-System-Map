#!/data/data/com.termux/files/usr/bin/bash
# install-on-pixel6.sh — Lays down the Sentinel watcher set on Pixel 6
# and wires it into the existing crontab. Idempotent.

set -e

SENTINEL_DIR="$HOME/sentinel"
mkdir -p "$SENTINEL_DIR/lib" "$SENTINEL_DIR/state" "$SENTINEL_DIR/logs"

# Watchers are assumed to have been scp'd into ~/sentinel/ already (lib/ + .sh)
chmod +x ~/sentinel/*.sh ~/sentinel/lib/*.sh 2>/dev/null

# Wire crontab — preserve heartbeat, add Sentinel entries
CRON_TMP=$(mktemp)
crontab -l 2>/dev/null | grep -v '/sentinel/' > "$CRON_TMP" || true

cat >> "$CRON_TMP" <<'CRON'
# --- HARK Sentinel ---
*/5 * * * * ~/sentinel/watch-pi-health.sh   >> ~/sentinel/logs/pi-health.log   2>&1
*/5 * * * * ~/sentinel/watch-cannamax.sh    >> ~/sentinel/logs/cannamax.log    2>&1
*/10 * * * * ~/sentinel/watch-hark-map.sh   >> ~/sentinel/logs/hark-map.log    2>&1
*/10 * * * * ~/sentinel/watch-pixel10.sh    >> ~/sentinel/logs/pixel10.log     2>&1
CRON

crontab "$CRON_TMP"
rm "$CRON_TMP"

# Make sure crond is running
crond 2>/dev/null || true

echo "=== Sentinel installed ==="
crontab -l | grep -E "sentinel|hark-heartbeat"
echo ""
echo "Logs: ~/sentinel/logs/  |  Digest: ~/sentinel/digest.log  |  State: ~/sentinel/state/"
