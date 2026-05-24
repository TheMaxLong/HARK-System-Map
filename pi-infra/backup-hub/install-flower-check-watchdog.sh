#!/usr/bin/env bash
# install-flower-check-watchdog.sh — wires the cross-watchdog into backup-hub's
# crontab. Idempotent. No alexandria clone or controller access needed — this
# only polls ntfy for the anderson-hub heartbeat.

set -euo pipefail

WATCHER_SRC="$(cd "$(dirname "$0")" && pwd)/watch-flower-check.sh"
WATCHER_DEST="${WATCHER_DEST:-$HOME/.hark/bin/watch-flower-check.sh}"
CRON_SCHEDULE="${CRON_SCHEDULE:-*/5 * * * *}"
CRON_TAG="# --- HARK flower-check watchdog ---"

mkdir -p "$(dirname "$WATCHER_DEST")" "$HOME/.hark/flower-check-watchdog"
cp "$WATCHER_SRC" "$WATCHER_DEST"
chmod +x "$WATCHER_DEST"

CRON_TMP=$(mktemp)
crontab -l 2>/dev/null | grep -vE 'HARK flower-check watchdog|watch-flower-check\.sh' > "$CRON_TMP" || true
cat >> "$CRON_TMP" <<EOF
$CRON_TAG
$CRON_SCHEDULE $WATCHER_DEST
EOF
crontab "$CRON_TMP"
rm "$CRON_TMP"

echo "=== Installed flower-check watchdog ==="
echo "watcher:   $WATCHER_DEST"
echo "schedule:  $CRON_SCHEDULE"
echo "stale at:  \${STALE_SEC:-720}s"
echo "logs:      $HOME/.hark/flower-check-watchdog/watchdog.log"
echo ""
crontab -l | grep -E 'flower-check' || true
