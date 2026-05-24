#!/usr/bin/env bash
# watch-flower-check.sh — runs on backup-hub. Cross-watchdog for the
# anderson-hub flower lights-out checker.
#
# The checker on anderson-hub posts a min-priority "HARK Flower Check"
# heartbeat to ntfy every run (every 5 min). This watchdog polls for that
# heartbeat and pages if it goes stale — which means the room-watcher itself
# has died (cron stopped, Node crash, bad git pull, tag-map parse error) even
# though the Pi may still be up and answering pings. That's the AB1 blind spot
# one level up: don't just watch the device, watch that the watcher is working.
#
# backup-hub is always-on and has the same Tailscale subnet route into
# 10.10.13.x, so it could run the check itself (hot standby) later. Today it
# only watches — no controller access is used by this script.

set -uo pipefail

TOPIC="${NTFY_TOPIC:-hark-phones-b6d6f70e9913}"
HEARTBEAT_TITLE="${HEARTBEAT_TITLE:-HARK Flower Check}"
STALE_SEC="${STALE_SEC:-720}"          # 12 min = 2 missed 5-min cycles + buffer
THROTTLE_MIN="${THROTTLE_MIN:-30}"
STATE_DIR="${STATE_DIR:-$HOME/.hark/flower-check-watchdog}"
LOG_FILE="$STATE_DIR/watchdog.log"
mkdir -p "$STATE_DIR"

now_epoch() { date +%s; }

# alert KEY TITLE MSG — throttled high-priority page to the human topic.
alert() {
  local KEY="$1" TITLE="$2" MSG="$3"
  local STAMP="$STATE_DIR/throttle.$KEY"
  local NOW; NOW=$(now_epoch)
  if [[ -f "$STAMP" ]]; then
    local LAST AGE; LAST=$(cat "$STAMP"); AGE=$((NOW - LAST))
    (( AGE < THROTTLE_MIN * 60 )) && return 0
  fi
  echo "$NOW" > "$STAMP"
  curl -s -o /dev/null --max-time 10 \
    -H "Title: $TITLE" -H "Priority: 5" -H "Tags: rotating_light,zzz" \
    -d "$MSG" "https://ntfy.sh/$TOPIC"
  echo "[$(date -u +%FT%TZ)] FIRED $KEY: $MSG" >> "$LOG_FILE"
}

# Latest epoch time of a heartbeat message matching the title, within 30 min.
LATEST=$(curl -s --max-time 8 "https://ntfy.sh/$TOPIC/json?poll=1&since=30m" 2>/dev/null \
  | HEARTBEAT_TITLE="$HEARTBEAT_TITLE" python3 -c '
import sys, json, os
title = os.environ["HEARTBEAT_TITLE"]
latest = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        if d.get("title", "") == title:
            latest = max(latest, d.get("time", 0))
    except Exception:
        pass
print(latest)
' 2>/dev/null)

NOW=$(now_epoch)
LATEST=${LATEST:-0}

if [[ "$LATEST" == "0" ]]; then
  alert "flower-check-silent" "Room-watcher SILENT" \
    "No '$HEARTBEAT_TITLE' heartbeat from anderson-hub in 30 min. The flower lights-out checker may be down — rooms are UNWATCHED. Check anderson-hub cron."
  exit 0
fi

AGE=$((NOW - LATEST))
if (( AGE > STALE_SEC )); then
  alert "flower-check-stale" "Room-watcher STALE" \
    "anderson-hub flower lights-out checker last ran ${AGE}s ago (expected every 300s). Rooms may be unwatched — check the Pi cron."
else
  echo "[$(date -u +%FT%TZ)] OK — last heartbeat ${AGE}s ago" >> "$LOG_FILE"
fi
