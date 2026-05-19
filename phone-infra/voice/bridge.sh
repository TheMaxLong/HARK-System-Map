#!/bin/bash
# bridge.sh — Mac-side daemon that polls a phone's voice inbox over SSH,
# processes new transcripts, and writes responses back to the phone's outbox.
#
# Usage: ./bridge.sh [phone_host]   (default: pixel6)

set -e

PHONE="${1:-pixel6}"
INBOX_REMOTE='hark-voice/inbox'
OUTBOX_REMOTE='hark-voice/outbox'
INBOX_LOCAL="$HOME/Documents/hark-voice/inbox"
OUTBOX_LOCAL="$HOME/Documents/hark-voice/outbox"
PROCESSED="$HOME/.hark/voice-processed.list"
LOGFILE="$HOME/.hark/voice-bridge.log"

mkdir -p "$INBOX_LOCAL" "$OUTBOX_LOCAL" "$(dirname "$LOGFILE")"
touch "$PROCESSED"

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOGFILE"
}

generate_response() {
  local TRANSCRIPT="$1"
  python3 - "$TRANSCRIPT" <<'PYEOF'
import json, os, sys, urllib.request

transcript = sys.argv[1]
if not transcript.strip():
    print("I didn't catch that.")
    sys.exit(0)

req = urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    headers={
        "x-api-key": os.environ["ANTHROPIC_API_KEY"],
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    },
    data=json.dumps({
        "model": "claude-haiku-4-5",
        "max_tokens": 400,
        "system": (
            "You are Claude, talking to Max over push-to-talk on his phone. "
            "Your reply will be read aloud by Android TTS. "
            "Rules: 1-3 sentences typical, 5 max. No markdown, no code blocks, no bullets — "
            "spoken sentences only. Direct and warm. Match his energy. "
            "If he asks for something that needs real tools, say you'd need him at the terminal for that. "
            "Context: Max runs HARK, his cannabis cultivation OS. Night-shift operator. You know him."
        ),
        "messages": [{"role": "user", "content": transcript}],
    }).encode(),
)
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        body = json.loads(r.read())
        text = "".join(b.get("text", "") for b in body.get("content", []))
        print(text.strip() or "I got an empty reply, try again.")
except Exception as e:
    print(f"Bridge error: {type(e).__name__}")
PYEOF
}

log "=== Bridge daemon started — watching $PHONE ==="
log "Local inbox mirror: $INBOX_LOCAL"
log "Phone inbox path:   $INBOX_REMOTE"

while true; do
  # List unprocessed files on phone
  FILES=$(ssh -o ConnectTimeout=5 "$PHONE" "ls $INBOX_REMOTE/*.txt 2>/dev/null | xargs -n1 basename 2>/dev/null" || true)

  for FNAME in $FILES; do
    if grep -qxF "$FNAME" "$PROCESSED" 2>/dev/null; then continue; fi

    log "New transcript: $FNAME"

    # Pull
    if scp -q "$PHONE:$INBOX_REMOTE/$FNAME" "$INBOX_LOCAL/$FNAME" 2>>"$LOGFILE"; then
      TRANSCRIPT=$(cat "$INBOX_LOCAL/$FNAME")
      log "  Transcript: \"$TRANSCRIPT\""

      RESPONSE=$(generate_response "$TRANSCRIPT")
      log "  Response:   \"$RESPONSE\""

      # Write local copy
      echo "$RESPONSE" > "$OUTBOX_LOCAL/$FNAME"

      # Push to phone
      if scp -q "$OUTBOX_LOCAL/$FNAME" "$PHONE:$OUTBOX_REMOTE/$FNAME" 2>>"$LOGFILE"; then
        log "  Pushed response to phone."
        # Remove the inbox file on phone so it doesn't reprocess
        ssh -o ConnectTimeout=5 "$PHONE" "rm $INBOX_REMOTE/$FNAME" 2>>"$LOGFILE" || true
        echo "$FNAME" >> "$PROCESSED"
      else
        log "  scp push FAILED"
      fi
    else
      log "  scp pull FAILED"
    fi
  done

  sleep 2
done
