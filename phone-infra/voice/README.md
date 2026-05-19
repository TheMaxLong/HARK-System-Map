# Push-to-Talk Voice Bridge v1

One-button conversation with Claude from your phone. Speak (or type) → transcript reaches Mac → Claude's reply comes back → phone speaks it.

**Status:** MVP. File-based architecture, no external APIs, no cloud.

---

## Architecture

```
Phone                          Mac                     Claude
-------                        ---                     ------
[ TALK button ]
  |
  v
talk.sh (record or input)
  |
  +--[microphone]---> transcribe (termux-speech-to-text)
  |
  +--[text input]----> manual transcript
  |
  v
Write: ~/hark-voice/inbox/YYYYMMDD-HHMMSS.txt
  |
  +---[SSH or file-share]---> ~/Documents/hark-voice/inbox/
                                |
                                v
                            bridge.sh (watches inbox)
                                |
                                v
                            Claude session reads transcript
                            (manual trigger via `claude` CLI or similar)
                                |
                                v
                            Claude writes response
                            Write: ~/Documents/hark-voice/outbox/YYYYMMDD-HHMMSS.txt
                                |
                                +---[SSH or file-share]---> ~/hark-voice/outbox/
                                                              |
                                                              v
                                                          speak.sh (watches outbox)
                                                              |
                                                              v
                                                          termux-tts-speak
                                                              |
                                                              v
                                                          [ Audio plays ]
```

---

## v1 Limitations & Capabilities

**What works today:**
- Text input (manual typing via phone terminal)
- File-based inbox/outbox (no cloud, no external APIs)
- TTS response (termux-tts-speak, built-in Android TTS)
- Multiple devices (Pixel 6, Pixel 10, any Termux)
- Tailscale-native (no public network exposure)

**What requires phone-side permission grant:**
- Microphone recording (termux-speech-to-text)
- Requires: You grant `RECORD_AUDIO` permission to Termux:API in Android Settings

**What's not in v1:**
- Automatic Claude session trigger (requires manual `claude` command on Mac)
- Cloud sync (purely local file-based)
- Web UI frontend

---

## Setup

### 1. Grant Microphone Permission (Optional, for speech-to-text)

On **Pixel 6** or **Pixel 10**:
1. Go to Settings > Apps > Termux:API > Permissions
2. Enable "Record audio"

If you skip this, the script falls back to manual text input.

### 2. Create Voice Directories

On **Mac**:
```bash
mkdir -p ~/Documents/hark-voice/inbox ~/Documents/hark-voice/outbox
mkdir -p ~/.hark
```

On **Phone** (Pixel 6 or 10, via SSH or direct Termux terminal):
```bash
mkdir -p ~/hark-voice/inbox ~/hark-voice/outbox
mkdir -p ~/.hark
```

### 3. Deploy Scripts to Phone

From Mac terminal:
```bash
cd ~/Documents/GitHub/HARK-System-Map/phone-infra/voice

# Copy phone scripts to Pixel 6
scp talk.sh pixel6:~/talk.sh
scp speak.sh pixel6:~/speak.sh
ssh pixel6 'chmod +x ~/talk.sh ~/speak.sh'

# Or to Pixel 10
scp talk.sh pixel10:~/talk.sh
scp speak.sh pixel10:~/speak.sh
ssh pixel10 'chmod +x ~/talk.sh ~/speak.sh'
```

### 4. Make Scripts Executable on Mac

```bash
chmod +x ~/Documents/GitHub/HARK-System-Map/phone-infra/voice/bridge.sh
chmod +x ~/Documents/GitHub/HARK-System-Map/phone-infra/voice/talk.sh
chmod +x ~/Documents/GitHub/HARK-System-Map/phone-infra/voice/speak.sh
```

### 5. (Optional) Install Termux Widget Shortcut

If you have Termux Widget app installed:

```bash
# On phone, via Termux terminal
mkdir -p ~/.shortcuts
cp ~/talk.sh ~/.shortcuts/talk
chmod +x ~/.shortcuts/talk
```

Then in Termux Widget app, add a shortcut pointing to "talk".

---

## Usage: Manual Flow

**Step 1: Start the bridge daemon on Mac (new terminal)**

```bash
~/.hark/run-voice-bridge.sh
# or manually:
~/Documents/GitHub/HARK-System-Map/phone-infra/voice/bridge.sh --watch
```

**Step 2: Start the speak daemon on phone (optional, for auto-speak)**

```bash
# On phone via SSH or Termux terminal
~/speak.sh &
```

Or skip this — you'll manually read the response file later.

**Step 3: Press the TALK button on phone**

```bash
# Via Termux Widget (if installed), or via SSH/terminal
~/talk.sh
```

This will:
1. Try to record audio (if RECORD_AUDIO permission granted)
2. Fall back to manual text input (if not)
3. Wait for response from Claude

**Step 4: Process on Mac**

Meanwhile, the bridge daemon sees the inbox file and... does nothing yet (v1 placeholder).

You manually run a Claude session that:
1. Reads `/Users/max/Documents/hark-voice/inbox/YYYYMMDD-HHMMSS.txt`
2. Gets your transcript
3. Writes response to `/Users/max/Documents/hark-voice/outbox/YYYYMMDD-HHMMSS.txt`

Example:
```bash
cat ~/Documents/hark-voice/inbox/20260519-115000.txt
# Output: "what's the weather"

# Now manually craft a response (or use Claude API):
echo "The weather today is sunny and 72 degrees." > ~/Documents/hark-voice/outbox/20260519-115000.txt
```

**Step 5: Phone Reads Response**

The phone's `talk.sh` (still waiting) sees the response file, reads it, calls TTS, and speaks it.

Or if `speak.sh` is running in background, it auto-detects and speaks.

---

## Testing the Flow (Manual)

### Test 1: Text Input → Echo Response

**On phone:**
```bash
~/talk.sh
# (type) hello world
# (Ctrl+D)
# [Waiting for response...]
```

**On Mac (in another terminal):**
```bash
# Wait 2 seconds, then:
LATEST=$(ls -t ~/Documents/hark-voice/inbox/*.txt | head -1)
echo "I heard: $(cat $LATEST)" > ~/Documents/hark-voice/outbox/$(basename $LATEST)
```

**On phone (same terminal as talk.sh):**
```
Claude says:
I heard: hello world

Speaking response...
[TTS audio plays]
```

### Test 2: With Bridge Daemon (Placeholder)

**On Mac (terminal 1):**
```bash
./bridge.sh --watch
# [watches inbox]
```

**On Mac (terminal 2):**
```bash
~/talk.sh
# (type) hello world
# (Ctrl+D)
# [Waiting...]
```

**On Mac (terminal 1):**
```
[timestamp] Processing: 20260519-115000
[timestamp] Transcript: hello world
[timestamp] Response: I heard you say: 'hello world'
[timestamp] Response written to /Users/max/Documents/hark-voice/outbox/20260519-115000.txt
```

**On phone (same terminal as talk.sh):**
```
Claude says:
I heard you say: 'hello world'

Speaking response...
[TTS audio plays]
```

---

## Logs

**Phone:**
- `~/.hark/voice.log` — talk.sh log
- `~/.hark/voice-speak.log` — speak.sh log

**Mac:**
- `~/.hark/voice-bridge.log` — bridge.sh log

View live:
```bash
tail -f ~/.hark/voice-bridge.log
```

---

## Troubleshooting

**Phone says "STT failed, falling back to manual input" but I granted RECORD_AUDIO**

Check:
1. Does Termux:API APK exist on phone? `ls -la /data/data/com.termux.api/`
2. Is permission actually granted? Check Android Settings > Apps > Termux:API > Permissions
3. Try manual test: `termux-speech-to-text` — does it hang or return text?

**Phone doesn't speak response**

Check:
1. Response file created? `ls ~/hark-voice/outbox/`
2. TTS permission? Try `termux-tts-speak "test"` directly
3. Is `speak.sh` running? `ps aux | grep speak.sh`

**Bridge daemon doesn't see inbox file**

Check:
1. File created? `ls ~/Documents/hark-voice/inbox/`
2. Permissions? `ls -la ~/Documents/hark-voice/inbox/`
3. Is `talk.sh` actually writing? Check `~/.hark/voice.log`

---

## Next: Integration with Claude

v1 uses placeholder responses. For real Claude integration:

1. **Option A (recommended):** Modify `bridge.sh` to call Claude API directly (requires API key in env)
2. **Option B:** Pipe transcript to an interactive Claude session (requires user interaction)
3. **Option C:** Use ntfy.sh topic-based handoff (adds external dependency but solves the session trigger problem)

For now, v1 is a working **proof of concept** that the file-based architecture works.

---

## File Manifest

```
phone-infra/voice/
├── talk.sh                 # Phone: record/input + wait for response
├── speak.sh                # Phone: watch outbox and speak responses
├── bridge.sh               # Mac: watch inbox and create responses
├── widget.sh               # Template for Termux Widget shortcut
└── README.md               # This file
```

---

## Architecture Rationale

**Why file-based instead of ntfy.sh?**
- Fewer external dependencies
- Simpler to debug (files are readable)
- Works offline
- Faster iteration

**Why not a full Claude session bridge?**
- Claude Code sessions are interactive (require user prompts)
- v1 aims for "tap button → wait → response" with minimal setup
- Integration can come later

**Why not WebSocket or HTTP?**
- Adds complexity for a v1
- File-based works across any transport (SSH, Syncthing, etc.)
- Phone-native, no server needed

---

## Commands Reference

Start bridge daemon:
```bash
./bridge.sh --watch          # continuous (Ctrl+C to stop)
./bridge.sh --once           # process one file
```

Start speak daemon:
```bash
~/speak.sh &                 # background on phone
```

Test manually:
```bash
# Phone
~/talk.sh

# Mac
LATEST=$(ls -t ~/Documents/hark-voice/inbox/*.txt | head -1)
echo "Test response" > ~/Documents/hark-voice/outbox/$(basename $LATEST)
```

Clean up:
```bash
rm -rf ~/Documents/hark-voice/
rm -rf ~/.hark/voice*
```
