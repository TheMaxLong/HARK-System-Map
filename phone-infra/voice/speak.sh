#!/data/data/com.termux/files/usr/bin/bash
# speak.sh — Phone daemon that watches outbox and speaks responses
# Typically runs in background via crond or direct invocation

set -e

OUTBOX="$HOME/hark-voice/outbox"
PROCESSED="$HOME/.hark/voice-processed"
LOGFILE="$HOME/.hark/voice-speak.log"

mkdir -p "$OUTBOX" "$PROCESSED"
mkdir -p "$(dirname "$LOGFILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
  echo "$*"
}

log "=== Speak daemon started ==="

while true; do
  # Find newest unprocessed response file
  for OUTFILE in $(ls -t "$OUTBOX"/*.txt 2>/dev/null); do
    if [ ! -f "$PROCESSED/$(basename "$OUTFILE")" ]; then
      RESPONSE=$(cat "$OUTFILE")
      log "Speaking: $RESPONSE"

      # Speak the response
      termux-tts-speak "$RESPONSE" || log "TTS failed for: $RESPONSE"

      # Mark as processed
      touch "$PROCESSED/$(basename "$OUTFILE")"
      log "Marked as processed: $(basename "$OUTFILE")"
    fi
  done

  sleep 1
done
