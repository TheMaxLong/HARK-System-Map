#!/data/data/com.termux/files/usr/bin/bash
# Shared Sentinel helpers — sourced by every watcher.

# Termux cron strips PATH; restore it so python3/curl/etc. resolve.
export PATH="$PATH:/data/data/com.termux/files/usr/bin"

SENTINEL_DIR="$HOME/sentinel"
STATE_DIR="$SENTINEL_DIR/state"
LOG_DIR="$SENTINEL_DIR/logs"
DIGEST_FILE="$SENTINEL_DIR/digest.log"  # what Claude reads next session
NTFY_TOPIC="hark-phones-b6d6f70e9913"
THROTTLE_MIN=30

mkdir -p "$STATE_DIR" "$LOG_DIR"

now_ts() { date '+%Y-%m-%d %H:%M:%S'; }
now_epoch() { date +%s; }

# log_digest LEVEL WATCHER MESSAGE
# Appends a structured line to digest.log for Claude to read on next session.
log_digest() {
  local LEVEL="$1" WATCHER="$2" MSG="$3"
  echo "$(now_ts) [$LEVEL] $WATCHER: $MSG" >> "$DIGEST_FILE"
}

# alert_throttled KEY LEVEL TITLE MESSAGE
# Sends ntfy + TTS unless the same KEY was fired within THROTTLE_MIN minutes.
# LEVEL: info|warn|critical
alert_throttled() {
  local KEY="$1" LEVEL="$2" TITLE="$3" MSG="$4"
  local STAMP="$STATE_DIR/throttle.$KEY"
  local NOW=$(now_epoch)
  if [ -f "$STAMP" ]; then
    local LAST=$(cat "$STAMP")
    local AGE=$((NOW - LAST))
    if [ $AGE -lt $((THROTTLE_MIN * 60)) ]; then return 0; fi
  fi
  echo "$NOW" > "$STAMP"

  local PRIORITY=3
  [ "$LEVEL" = "warn" ] && PRIORITY=4
  [ "$LEVEL" = "critical" ] && PRIORITY=5

  curl -s -X POST \
    -H "Title: $TITLE" \
    -H "Priority: $PRIORITY" \
    -d "$MSG" "https://ntfy.sh/$NTFY_TOPIC" > /dev/null
  # Only TTS on warn/critical to avoid noise
  if [ "$LEVEL" != "info" ]; then
    termux-tts-speak "$TITLE. $MSG" 2>/dev/null
  fi
  log_digest "$LEVEL" "$KEY" "$MSG"
}
