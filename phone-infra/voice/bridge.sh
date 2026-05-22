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
import json, os, sys, time, urllib.request, urllib.error

transcript = sys.argv[1]
if not transcript.strip():
    print("I didn't catch that.")
    sys.exit(0)

payload = json.dumps({
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
}).encode()

RETRYABLE = {408, 425, 429, 500, 502, 503, 504, 529}
MAX_ATTEMPTS = 4

for attempt in range(1, MAX_ATTEMPTS + 1):
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": os.environ.get("ANTHROPIC_API_KEY", ""),
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        data=payload,
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            body = json.loads(r.read())
            text = "".join(b.get("text", "") for b in body.get("content", []))
            print(text.strip() or "I got an empty reply, try again.")
            sys.exit(0)
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode("utf-8", errors="replace")[:300]
        except Exception:
            err_body = ""
        print(f"[bridge] attempt {attempt}: HTTP {e.code} {e.reason} :: {err_body}", file=sys.stderr)
        if e.code in RETRYABLE and attempt < MAX_ATTEMPTS:
            time.sleep(1.5 * attempt)
            continue
        if e.code == 401:
            print("My API key got rejected. Check the bridge config.")
        elif e.code == 429:
            print("Hit the rate limit, give it a minute.")
        elif e.code in RETRYABLE:
            print("Anthropic is overloaded right now, try again in a sec.")
        else:
            print(f"API returned {e.code}, give it another shot.")
        sys.exit(0)
    except urllib.error.URLError as e:
        print(f"[bridge] attempt {attempt}: URLError {e.reason}", file=sys.stderr)
        if attempt < MAX_ATTEMPTS:
            time.sleep(1.5 * attempt)
            continue
        print("Network's not reaching Anthropic, check the Mac connection.")
        sys.exit(0)
    except Exception as e:
        print(f"[bridge] attempt {attempt}: {type(e).__name__} {e}", file=sys.stderr)
        print("Something choked on the bridge, try again.")
        sys.exit(0)
PYEOF
}

# SSH/SCP options — ConnectTimeout protects the dial; ServerAliveInterval +
# ServerAliveCountMax kill the session if the remote stops talking mid-flight
# (without these, a half-dead connection wedges the polling loop forever).
SSH_OPTS=(-o ConnectTimeout=5 -o ServerAliveInterval=3 -o ServerAliveCountMax=2 -o BatchMode=yes)
# `timeout` belt-and-suspenders cap on the whole call. Need gtimeout on macOS.
TIMEOUT_CMD=$(command -v gtimeout || command -v timeout || echo "")
ssh_call()  { [ -n "$TIMEOUT_CMD" ] && "$TIMEOUT_CMD" 15 ssh "${SSH_OPTS[@]}" "$@" || ssh "${SSH_OPTS[@]}" "$@"; }
scp_call()  { [ -n "$TIMEOUT_CMD" ] && "$TIMEOUT_CMD" 20 scp "${SSH_OPTS[@]}" "$@" || scp "${SSH_OPTS[@]}" "$@"; }

log "=== Bridge daemon started — watching $PHONE ==="
log "Local inbox mirror: $INBOX_LOCAL"
log "Phone inbox path:   $INBOX_REMOTE"
log "timeout cmd: ${TIMEOUT_CMD:-NONE (sessions will rely on ServerAlive only)}"

while true; do
  # List unprocessed files on phone
  FILES=$(ssh_call "$PHONE" "ls $INBOX_REMOTE/*.txt 2>/dev/null | xargs -n1 basename 2>/dev/null" || true)

  for FNAME in $FILES; do
    if grep -qxF "$FNAME" "$PROCESSED" 2>/dev/null; then continue; fi

    log "New transcript: $FNAME"

    # Pull
    if scp_call -q "$PHONE:$INBOX_REMOTE/$FNAME" "$INBOX_LOCAL/$FNAME" 2>>"$LOGFILE"; then
      TRANSCRIPT=$(cat "$INBOX_LOCAL/$FNAME")
      log "  Transcript: \"$TRANSCRIPT\""

      RESPONSE=$(generate_response "$TRANSCRIPT")
      log "  Response:   \"$RESPONSE\""

      # Write local copy
      echo "$RESPONSE" > "$OUTBOX_LOCAL/$FNAME"

      # Push to phone
      if scp_call -q "$OUTBOX_LOCAL/$FNAME" "$PHONE:$OUTBOX_REMOTE/$FNAME" 2>>"$LOGFILE"; then
        log "  Pushed response to phone."
        # Remove the inbox file on phone so it doesn't reprocess
        ssh_call "$PHONE" "rm $INBOX_REMOTE/$FNAME" 2>>"$LOGFILE" || true
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
