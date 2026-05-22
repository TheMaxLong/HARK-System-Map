#!/usr/bin/env bash
# install-flower-lights-out-check.sh — Wires the flower lights-out alert
# into anderson-hub's crontab. Idempotent: re-running it just refreshes
# the cron entry.
#
# Prerequisites on the Pi:
#   - Node 24+ + pnpm installed (pnpm is needed because the script uses
#     `pnpm --filter ... run check-lights-out` to invoke tsx)
#   - alexandria repo cloned at $ALEXANDRIA_DIR (default $HOME/alexandria)
#   - data/tag-maps/{AB,EF,GH}/flower-temps.json have real tag IDs
#     (script will still install if they're REPLACE_ME; it just won't fire
#     any alerts until you fill them in)
#   - Tailscale subnet route to 10.10.13.x is active

set -euo pipefail

ALEXANDRIA_DIR="${ALEXANDRIA_DIR:-$HOME/alexandria}"
WRAPPER_SRC="$(cd "$(dirname "$0")" && pwd)/run-flower-lights-out-check.sh"
WRAPPER_DEST="${WRAPPER_DEST:-$HOME/.hark/bin/run-flower-lights-out-check.sh}"
CRON_SCHEDULE="${CRON_SCHEDULE:-*/5 * * * *}"
CRON_TAG="# --- HARK flower-lights-out ---"

mkdir -p "$(dirname "$WRAPPER_DEST")" "$HOME/.hark/flower-lights-out"
cp "$WRAPPER_SRC" "$WRAPPER_DEST"
chmod +x "$WRAPPER_DEST"

if [[ ! -d "$ALEXANDRIA_DIR" ]]; then
  echo "WARN: alexandria not at $ALEXANDRIA_DIR — clone it before the cron will work" >&2
fi

# Refresh crontab — keep all other lines, replace just our block.
CRON_TMP=$(mktemp)
crontab -l 2>/dev/null | grep -vE 'HARK flower-lights-out|run-flower-lights-out-check\.sh' > "$CRON_TMP" || true
cat >> "$CRON_TMP" <<EOF
$CRON_TAG
$CRON_SCHEDULE $WRAPPER_DEST
EOF
crontab "$CRON_TMP"
rm "$CRON_TMP"

echo "=== Installed ==="
echo "wrapper:       $WRAPPER_DEST"
echo "alexandria:    $ALEXANDRIA_DIR"
echo "schedule:      $CRON_SCHEDULE"
echo "logs:          $HOME/.hark/flower-lights-out/last-run.log"
echo "ntfy topic:    \${NTFY_TOPIC:-hark-phones-b6d6f70e9913}"
echo ""
crontab -l | grep -E 'flower-lights-out|HARK' || true
