#!/data/data/com.termux/files/usr/bin/bash
# talk.sh — Record audio (via mic) or accept text input, send to Mac for Claude to respond
# Runs on: Pixel 6 or Pixel 10 (via SSH or local termux)

set -e

INBOX="$HOME/hark-voice/inbox"
OUTBOX="$HOME/hark-voice/outbox"
LOGFILE="$HOME/.hark/voice.log"

mkdir -p "$INBOX" "$OUTBOX"
mkdir -p "$(dirname "$LOGFILE")"

# Timestamp for file naming
TS=$(date +%Y%m%d-%H%M%S)
INFILE="$INBOX/$TS.txt"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
  echo "$*"
}

log "=== TALK SESSION START ==="

# Try to record audio via termux-speech-to-text
# Requires: android.permission.RECORD_AUDIO granted on the phone
# If permission not granted, this will fail with JSON error

echo "Recording audio... (speak now, or Ctrl+C to cancel)"
log "Attempting termux-speech-to-text..."

if TRANSCRIPT=$(termux-speech-to-text 2>&1); then
  log "STT succeeded: $TRANSCRIPT"
  echo "$TRANSCRIPT" > "$INFILE"
  echo "Transcript saved: $INFILE"
else
  # If STT fails (likely due to missing RECORD_AUDIO permission)
  # Fall back to manual text input
  log "STT failed, falling back to manual input"
  echo "Enter text for Claude (Ctrl+D when done):"
  TRANSCRIPT=$(cat)
  if [ -z "$TRANSCRIPT" ]; then
    log "Empty input, aborting"
    echo "No input provided."
    exit 1
  fi
  echo "$TRANSCRIPT" > "$INFILE"
  log "Manual input saved: $INFILE"
fi

echo "Waiting for response from Claude..."
log "Inbox file ready, waiting for outbox response at $OUTBOX/$TS.txt"

# Poll outbox for response (30 second timeout)
TIMEOUT=30
ELAPSED=0
POLL_INTERVAL=1

while [ $ELAPSED -lt $TIMEOUT ]; do
  if [ -f "$OUTBOX/$TS.txt" ]; then
    RESPONSE=$(cat "$OUTBOX/$TS.txt")
    log "Response received: $RESPONSE"

    echo
    echo "Claude says:"
    echo "$RESPONSE"
    echo

    # Read response aloud via TTS
    echo "Speaking response..."
    termux-tts-speak "$RESPONSE"

    # Cleanup
    rm "$OUTBOX/$TS.txt"
    log "Response file cleaned up"
    log "=== TALK SESSION END (SUCCESS) ==="
    exit 0
  fi

  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
  echo -n "."
done

log "=== TALK SESSION END (TIMEOUT) ==="
echo
echo "Timeout waiting for response from Claude. Is the inbox being processed?"
exit 1
