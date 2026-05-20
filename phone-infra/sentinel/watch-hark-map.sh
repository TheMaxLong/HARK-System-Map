#!/data/data/com.termux/files/usr/bin/bash
# watch-hark-map.sh — Diffs the HARK map state file vs. last seen.
# Logs new dream/market nodes and new notes for Claude to read next session.
# Quiet: never TTS or ntfy — pure logging.
source ~/sentinel/lib/common.sh

WATCHER=hark-map-drift
URL="https://raw.githubusercontent.com/TheMaxLong/HARK-System-Map/main/map-state.json"
LAST_FILE="$STATE_DIR/$WATCHER.last.json"
TMP_FILE="$STATE_DIR/$WATCHER.curr.json"

curl -s --max-time 10 "$URL?t=$(now_epoch)" -o "$TMP_FILE"
[ ! -s "$TMP_FILE" ] && exit 0

if [ ! -f "$LAST_FILE" ]; then
  cp "$TMP_FILE" "$LAST_FILE"
  log_digest info "$WATCHER" "initial snapshot captured"
  exit 0
fi

DIFF=$(python3 - <<PYEOF
import json
with open("$LAST_FILE") as f: prev = json.load(f)
with open("$TMP_FILE") as f: curr = json.load(f)

prev_ids = {n["id"] for n in prev.get("nodes", [])}
curr_ids = {n["id"] for n in curr.get("nodes", [])}
new_ids  = curr_ids - prev_ids
gone_ids = prev_ids - curr_ids

prev_notes = {n["id"]: (n.get("notes") or "") for n in prev.get("nodes", [])}
curr_notes = {n["id"]: (n.get("notes") or "") for n in curr.get("nodes", [])}

events = []
for nid in sorted(new_ids):
    node = next((n for n in curr["nodes"] if n["id"]==nid), {})
    cat = node.get("cat","?")
    label = node.get("label", nid)
    events.append(f"NEW [{cat}] node: {label}")
for nid in sorted(gone_ids):
    events.append(f"REMOVED node: {nid}")
for nid, note in curr_notes.items():
    prev_note = prev_notes.get(nid, "")
    if note and note != prev_note:
        label = next((n.get("label", nid) for n in curr["nodes"] if n["id"]==nid), nid)
        events.append(f"NOTE on {label}: {note[:100]}")

for e in events: print(e)
PYEOF
)

if [ -n "$DIFF" ]; then
  echo "$DIFF" | while IFS= read -r line; do
    log_digest info "$WATCHER" "$line"
  done
fi

cp "$TMP_FILE" "$LAST_FILE"
