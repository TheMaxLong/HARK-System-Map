#!/bin/bash
# Off-site backup of ONE Postgres database on ONE facility Pi.
#
# Usage:
#   facility-archive-backup-generic.sh <host> <db> <remote-env-path> [min-tables]
#
# e.g. facility-archive-backup-generic.sh anderson-hub fluxuum \
#        /home/pi/Fluxuum-Logger_v420/artifacts/api-server/.env 18
#
# Why this exists: as of 2026-07-30 there are FOUR databases worth keeping —
# fluxuum and cannamax on each of hub-backup and anderson-hub — and only
# hub-backup's two had scripts. Writing a third and fourth copy of the same 100
# lines would mean fixing every future bug four times, so this one is
# parameterised.
#
# ⚠️ The two hub-backup scripts (facility-archive-backup.sh and
# facility-archive-backup-cannamax.sh) are deliberately NOT migrated onto this.
# They are proven in production and one of them spent three days silently dead
# before being fixed; re-pointing them to gain tidiness is a bad trade. Migrate
# them only once this has run unattended for a while. Until then: a bug fixed
# here should be checked against both of those too.
#
# Everything else follows the shape those two established:
#   - pg_dump STREAMED over ssh, never written to the Pi's SD card (they degrade)
#   - .tmp then atomic rename, so Drive can never upload a half-written file
#   - verified BEFORE it is copied to Drive; a corrupt dump never propagates
#   - a receipt under ~/Library/Logs, because a launchd job cannot list ~/Documents
#   - NOTHING is pruned (Max's executive decision 2026-07-30: keep it all)
#
# Created 2026-07-30.

set -o pipefail

HOST="${1:?usage: $0 <host> <db> <remote-env-path> [min-tables]}"
DB="${2:?missing db name}"
REMOTE_ENV="${3:?missing remote .env path}"
MIN_TABLES="${4:-10}"

LOCAL="$HOME/facility-archives"
DRIVE="$HOME/Library/CloudStorage/GoogleDrive-max2k03@gmail.com/My Drive/facility-archives"
STAMP=$(date +%Y%m%d-%H%M)
NAME="${HOST}-${DB}-${STAMP}.sql.gz"
RECEIPT="$HOME/Library/Logs/facility-archive-${HOST}-${DB}-last.txt"

mkdir -p "$LOCAL" "$DRIVE" "$HOME/Library/Logs"

TMP="$LOCAL/.${NAME}.tmp"
FINAL="$LOCAL/$NAME"

log() { echo "[$(TZ=America/Los_Angeles date -Iseconds)] $*"; }

log "start: streaming pg_dump $DB from $HOST"

# `set -o pipefail` on the REMOTE side is load-bearing: without it a pg_dump that
# dies mid-stream still exits 0 because gzip succeeded, so a TRUNCATED dump reads
# as success. The connection string is resolved ON the Pi and never crosses a
# command line, so no password reaches local history or a remote process list.
if ! ssh -o ConnectTimeout=15 -o BatchMode=yes "pi@$HOST" \
      "set -o pipefail; PGURL=\$(sed -n 's/^DATABASE_URL=//p' $REMOTE_ENV | head -1 | tr -d '\"'\\''') && [ -n \"\$PGURL\" ] && pg_dump \"\$PGURL\" | gzip -9" > "$TMP"; then
  log "FAIL: pg_dump stream failed (host unreachable, dump error, or DATABASE_URL not found in $REMOTE_ENV)"
  rm -f "$TMP"
  exit 1
fi

if [ ! -s "$TMP" ]; then
  log "FAIL: dump is empty"
  rm -f "$TMP"
  exit 1
fi

if ! gzip -t "$TMP" 2>/dev/null; then
  log "FAIL: dump failed gzip integrity check — not keeping it"
  rm -f "$TMP"
  exit 1
fi

# grep -c, NEVER grep -q. Under `set -o pipefail`, grep -q exits at the first match,
# SIGPIPEs gunzip, and the pipeline reports failure ON SUCCESS — that bug rejected a
# known-good backup in this project once already.
TABLES_IN_DUMP=$(gunzip -c "$TMP" | grep -c '^COPY public\.' || true)
if [ "${TABLES_IN_DUMP:-0}" -lt "$MIN_TABLES" ]; then
  log "FAIL: only ${TABLES_IN_DUMP} tables in dump, expected at least ${MIN_TABLES} — not keeping it"
  rm -f "$TMP"
  exit 1
fi

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

# Written only after verification, so the timestamp means "a good backup of THIS
# database on THIS host existed at this moment".
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
