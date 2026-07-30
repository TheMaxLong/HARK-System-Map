#!/bin/bash
# Off-site backup of the CANNAMAX database on hub-backup.
#
# Why this exists separately from facility-archive-backup.sh:
#   Until 2026-07-30 only `fluxuum` was ever backed up. `cannamax` — 119MB holding
#   fluxuum_readings, runoff_station_readings, vision_runs, change_events — had
#   NEVER been copied off the Pi. Max: "SAVE ALL THE DATA... all the run info and
#   runoff." This closes that.
#
#   It is a separate file rather than a second database bolted into the fluxuum
#   script on purpose. That script had been silently dead for three days and was
#   only just fixed and proven; a bug introduced while generalising it would take
#   out the backup that finally works. Two simple scripts beat one clever one.
#   The cost is duplication — if you fix a bug here, check the sibling.
#
# Shape follows the sibling deliberately:
#   - pg_dump STREAMED over ssh, never written to the Pi's SD card (it is degrading)
#   - written to .tmp then atomically renamed, so Drive can never upload a partial
#   - local copy verified BEFORE it is copied to Drive; a corrupt dump never propagates
#   - a receipt in ~/Library/Logs so a scheduled job can confirm freshness without
#     needing to list ~/Documents, which macOS will not let launchd enumerate
#   - NOTHING is pruned. Max's executive decision 2026-07-30: keep it all.
#
# Created 2026-07-30.

set -o pipefail

HOST="hub-backup"
DB="cannamax"
# The connection string lives with the app that owns it, not with fluxuum's.
REMOTE_ENV="/home/pi/cannamax/demo/runoff-loader/.env"
LOCAL="$HOME/facility-archives"
DRIVE="$HOME/Library/CloudStorage/GoogleDrive-max2k03@gmail.com/My Drive/facility-archives"
STAMP=$(date +%Y%m%d-%H%M)
NAME="${HOST}-${DB}-${STAMP}.sql.gz"
RECEIPT="$HOME/Library/Logs/facility-archive-cannamax-last.txt"

mkdir -p "$LOCAL" "$DRIVE" "$HOME/Library/Logs"

TMP="$LOCAL/.${NAME}.tmp"
FINAL="$LOCAL/$NAME"

log() { echo "[$(TZ=America/Los_Angeles date -Iseconds)] $*"; }

log "start: streaming pg_dump $DB from $HOST"

# `set -o pipefail` in the REMOTE command matters: without it a pg_dump that dies
# mid-stream still exits 0 because gzip succeeded, and a TRUNCATED dump reads as a
# success. That exact hole existed in the fluxuum script for months.
#
# The connection string is resolved ON the Pi and never crosses a command line, so
# no password lands in local shell history or a remote process list.
if ! ssh -o ConnectTimeout=15 -o BatchMode=yes "pi@$HOST" \
      "set -o pipefail; PGURL=\$(sed -n 's/^DATABASE_URL=//p' $REMOTE_ENV | head -1 | tr -d '\"'\\''') && [ -n \"\$PGURL\" ] && pg_dump \"\$PGURL\" | gzip -9" > "$TMP"; then
  log "FAIL: pg_dump stream failed (host unreachable, dump error, or DATABASE_URL not found)"
  rm -f "$TMP"
  exit 1
fi

if [ ! -s "$TMP" ]; then
  log "FAIL: dump is empty"
  rm -f "$TMP"
  exit 1
fi

# Verify before trusting. gzip -t catches truncation; the table count catches a
# dump that streamed fine but contains almost nothing.
if ! gzip -t "$TMP" 2>/dev/null; then
  log "FAIL: dump failed gzip integrity check — not keeping it"
  rm -f "$TMP"
  exit 1
fi

# grep -c, never grep -q. Under `set -o pipefail`, grep -q exits at the first match,
# SIGPIPEs gunzip, and the pipeline reports failure ON SUCCESS. That bug rejected a
# known-good backup here once already.
TABLES_IN_DUMP=$(gunzip -c "$TMP" | grep -c '^COPY public\.' || true)
if [ "${TABLES_IN_DUMP:-0}" -lt 10 ]; then
  log "FAIL: only ${TABLES_IN_DUMP} tables in dump, expected ~15 — not keeping it"
  rm -f "$TMP"
  exit 1
fi

# Never overwrite an existing archive.
if [ -e "$FINAL" ]; then
  log "FAIL: $NAME already exists — refusing to overwrite"
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$FINAL"
SIZE=$(ls -lh "$FINAL" | awk '{print $5}')
log "local ok: $NAME ($SIZE, ${TABLES_IN_DUMP} tables)"

if cp "$FINAL" "$DRIVE/$NAME"; then
  log "drive ok: $NAME"
  DRIVE_OK=yes
else
  log "WARN: local copy is good but Drive copy failed"
  DRIVE_OK=no
fi

# Receipt: written only after the dump passed verification, so its timestamp means
# "a good cannamax backup existed at this moment". ~/Library/Logs because a launchd
# job can read there and cannot read ~/Documents.
{
  echo "name=$NAME"
  echo "size=$SIZE"
  echo "tables=$TABLES_IN_DUMP"
  echo "drive_ok=${DRIVE_OK:-unknown}"
  echo "epoch=$(date +%s)"
  echo "written=$(TZ=America/Los_Angeles date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "local_path=$FINAL"
} > "$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"
log "receipt written: $RECEIPT"

# Half-written temp files only. Archives are never pruned.
find "$LOCAL" -name ".${HOST}-${DB}-*.tmp" -mmin +120 -delete

# Third copy: the external drive. It is portable and usually unplugged, so this
# never fails the backup — the sync script reports `standby` when the drive is
# absent and catches up automatically the moment it is plugged in (launchd
# StartOnMount). Three copies, two kinds of media, one off-site.
bash "$HOME/bin/sync-archives-external.sh" >/dev/null 2>&1 || true

log "done"
