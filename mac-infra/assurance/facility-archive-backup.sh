#!/bin/bash
# Daily off-site backup of hub-backup's fluxuum DB (the DEEP ARCHIVE).
#
# Why this exists: hub-backup holds facility readings back to 2026-05-19 that
# exist NOWHERE else — anderson-hub only keeps ~30 days by design. hub-backup
# has no backup cron of its own and sits on a single SD card.
#
# Design notes:
#  - pg_dump is STREAMED over SSH and never written to hub-backup's SD card,
#    so this adds zero write-wear to the card it's protecting.
#  - Written to .tmp then atomically renamed, so Google Drive can never upload
#    a half-written file.
#  - Local copy first, verified, THEN copied to Drive. A corrupt dump never
#    reaches the cloud.
#  - Retention: 30 daily copies in each location.
#
# Created 2026-07-20.

set -o pipefail

HOST="hub-backup"
DB="fluxuum"
LOCAL="$HOME/facility-archives"
DRIVE="$HOME/Library/CloudStorage/GoogleDrive-max2k03@gmail.com/My Drive/facility-archives"
KEEP_DAYS=30
STAMP=$(date +%Y%m%d-%H%M)
NAME="${HOST}-${DB}-${STAMP}.sql.gz"

mkdir -p "$LOCAL" "$DRIVE"

TMP="$LOCAL/.${NAME}.tmp"
FINAL="$LOCAL/$NAME"

log() { echo "[$(date -Iseconds)] $*"; }

log "start: streaming pg_dump $DB from $HOST"

# Dumps as the `fluxuum` app role — NO sudo (changed 2026-07-29).
#
# Why: this used to run `sudo -u postgres pg_dump`. Over a BatchMode ssh with no
# tty, that only works while a sudo credential timestamp happens to be warm.
# Verified cold on hub-backup: 0 bytes, rc=1, "sudo: a password is required".
# It succeeded for months on luck and then quietly produced nothing — which is
# how this backup went dead for three days without anyone knowing.
#
# The `fluxuum` role was granted `pg_read_all_data` (Postgres 14+ predefined,
# read-only, no write or admin rights) so it can read `readings_archive` — the
# postgres-owned deep-archive table this backup exists to protect. Proven
# complete on both Pis: pg_dump rc=0, 20 of 20 catalog tables, archive included.
#
# The connection string is resolved ON THE PI with sed and never crosses into a
# command line, so the password appears in no local shell history and no remote
# process list. sed avoids the quote-nesting that an inline grep regex needs.
if ! ssh -o ConnectTimeout=15 -o BatchMode=yes "pi@$HOST" \
      'set -o pipefail; cd /home/pi/Fluxuum-Logger_v420/artifacts/api-server && PGURL=$(sed -n "s/^DATABASE_URL=//p" .env | head -1) && [ -n "$PGURL" ] && pg_dump "$PGURL" | gzip -9' > "$TMP"; then
  log "FAIL: pg_dump stream failed (host unreachable, dump error, or DATABASE_URL not found)"
  rm -f "$TMP"
  exit 1
fi
# NOTE on `set -o pipefail` in the REMOTE command above: without it, a pg_dump
# that dies mid-stream still leaves gzip exiting 0, so ssh returns 0 and a
# TRUNCATED dump looks like success. This flaw was in the original script too
# (`sudo -u postgres pg_dump $DB | gzip -9`) and is not new. The checks below
# would very likely catch a truncated dump anyway — but a backup script should
# not rely on "very likely".

# Verify before it counts as a backup.
if ! gzip -t "$TMP" 2>/dev/null; then
  log "FAIL: gzip integrity check failed — discarding"
  rm -f "$TMP"
  exit 1
fi

# Completeness check (hardened 2026-07-29).
#
# This used to count ONLY the `readings` block. That is not enough: on
# 2026-07-29 the history moved tables — `readings` went from 531,913 rows down to
# ~320,000 while a `readings_archive` of 232,648 appeared. A readings-only check
# would have called that shrink healthy. Worse, a dump taken as a role lacking
# access to `readings_archive` would omit 232k rows of irreplaceable history and
# still sail past a readings-only bar.
#
# So check three things: the archive table is actually present, the TABLE COUNT
# matches what the database says it has, and total history clears a floor.
count_block() {
  gunzip -c "$TMP" | awk -v tbl="$1" '
    $0 ~ "^COPY public\\." tbl " " {inr=1; next}
    inr && /^\\\.$/{inr=0}
    inr{n++}
    END{print n+0}'
}

TABLES_IN_DUMP=$(gunzip -c "$TMP" | grep -c '^COPY public\.')
TABLES_IN_DB=$(ssh -o ConnectTimeout=15 -o BatchMode=yes "pi@$HOST" \
  'cd /home/pi/Fluxuum-Logger_v420/artifacts/api-server && PGURL=$(sed -n "s/^DATABASE_URL=//p" .env | head -1) && psql "$PGURL" -At -c "select count(*) from pg_tables where schemaname='"'"'public'"'"';"' 2>/dev/null)

if [ -z "$TABLES_IN_DB" ]; then
  # Do not fail the whole backup because one metadata query hiccuped — but never
  # let this pass silently either. Silence is what let this backup die unnoticed
  # for three days. The archive-present and row-floor checks below still apply.
  log "WARN: could not read the live table count from $HOST — table-count check SKIPPED this run (dump has $TABLES_IN_DUMP tables)"
elif [ "$TABLES_IN_DUMP" != "$TABLES_IN_DB" ]; then
  log "FAIL: dump has $TABLES_IN_DUMP tables but database has $TABLES_IN_DB — refusing (incomplete dump)"
  rm -f "$TMP"
  exit 1
fi

# NOTE: use grep -c, NOT grep -q. This script runs with `set -o pipefail`, and
# `grep -q` exits the instant it matches, which SIGPIPEs the upstream gunzip.
# pipefail then reports the whole pipeline as failed *even though the pattern was
# found* — so a perfectly good backup gets rejected. grep -c reads to EOF.
ARCH_HDRS=$(gunzip -c "$TMP" | grep -c '^COPY public\.readings_archive')
if [ "$ARCH_HDRS" -lt 1 ]; then
  log "FAIL: dump is missing readings_archive (the deep archive) — refusing to accept as a backup"
  rm -f "$TMP"
  exit 1
fi

ROWS=$(count_block readings)
ARCH=$(count_block readings_archive)
TOTAL=$(( ROWS + ARCH ))

# Floor sits below the 553,323 total observed 2026-07-29, with headroom for
# normal retention trimming, but far above any truncated or partial dump.
if [ "$TOTAL" -lt 400000 ]; then
  log "FAIL: only $TOTAL total history rows (readings=$ROWS archive=$ARCH) — refusing to accept as a backup"
  rm -f "$TMP"
  exit 1
fi

# Never overwrite an existing backup. A same-minute re-run must not clobber one.
if [ -e "$FINAL" ]; then
  log "FAIL: $NAME already exists — refusing to overwrite an existing backup"
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$FINAL"
SIZE=$(ls -lh "$FINAL" | awk '{print $5}')
log "local ok: $NAME ($SIZE, ${TABLES_IN_DUMP} tables, readings=$ROWS archive=$ARCH total=$TOTAL)"

if cp "$FINAL" "$DRIVE/$NAME"; then
  log "drive ok: $NAME"
  DRIVE_OK=yes
else
  log "WARN: local copy is good but Drive copy failed"
  DRIVE_OK=no
fi

# Leave a receipt somewhere a SCHEDULED job can actually read.
#
# 2026-07-30: the staleness alarm cried "Facility Archive Empty" at 09:00 while a
# 17MB backup from 03:00 sat in the folder. macOS lets a launchd job stat
# ~/Documents and then hands it an EMPTY listing, because that path is protected.
# ~/Library/CloudStorage is protected the same way, so checking the Drive copy
# instead fixes nothing — verified by running the alarm through launchd, not by
# hand. ~/Library/Logs IS readable, which is why this file lives here.
#
# Written only after the dump passed its own verification, so its timestamp means
# "a good backup existed at this moment" — which is the only thing the alarm
# actually needs to know. If this job dies, the receipt stops moving and the
# alarm correctly goes stale.
RECEIPT="$HOME/Library/Logs/facility-archive-last.txt"
{
  echo "name=$NAME"
  echo "size=$SIZE"
  echo "drive_ok=${DRIVE_OK:-unknown}"
  echo "epoch=$(date +%s)"
  echo "written=$(TZ=America/Los_Angeles date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "local_path=$FINAL"
} > "$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"
log "receipt written: $RECEIPT"

# Prune both locations. Only ever removes files this script created.
#
# 2026-07-30: the pattern below also matched
# `hub-backup-fluxuum-DEEPARCHIVE-20260720-1036.sql.gz`, which was therefore due
# to be deleted from BOTH copies on 2026-08-19. That file is the only copy of the
# May 19 - Jun 20 readings. The rolling 30-day window is right for the nightly
# dumps — they supersede each other — and completely wrong for a deep archive,
# which is kept precisely because nothing else holds that period.
# `! -name '*DEEPARCHIVE*'` is what keeps them apart.
# 2026-07-30, second fix: a flat 30-day window is not an archive, it is a moving
# window, and Max believed off-site kept forever. Nothing on either Pi deletes
# readings today — verified, no cron, no timer, no app code — so nothing is
# ageing out right now. But the day someone tidies the database by hand, the only
# record of what was there is a dump, and a 30-day dump has usually already gone.
#
# So: keep every dump 30 days, AND keep the FIRST dump of each calendar month
# forever. ~220MB a year. The keeper is chosen as the earliest file we still hold
# for that month rather than "the one dated the 1st", because the job can miss a
# day — it missed 27 and 28 July — and a rule keyed to a date that never got
# written keeps nothing at all.
prune_dir() {
  dir="$1"
  [ -d "$dir" ] || return 0

  # Filenames carry YYYYMMDD-HHMM, so sorting by name sorts by time. First one
  # seen per YYYYMM is that month's keeper.
  keepers=$(ls -1 "$dir"/${HOST}-${DB}-*.sql.gz 2>/dev/null | sed 's|.*/||' \
    | grep -v DEEPARCHIVE | sort \
    | awk 'match($0, /[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]/) {
             ym = substr($0, RSTART, 6); if (!(ym in seen)) { seen[ym]=1; print }
           }' || true)

  for f in "$dir"/${HOST}-${DB}-*.sql.gz; do
    [ -e "$f" ] || continue
    base=${f##*/}
    case "$base" in *DEEPARCHIVE*) continue ;; esac
    # grep -c, never grep -q: -q exits early, SIGPIPEs the upstream printf, and
    # `set -o pipefail` then reports failure on a successful match.
    hit=$(printf '%s\n' "$keepers" | grep -cxF -- "$base" || true)
    [ "${hit:-0}" -gt 0 ] && continue
    if [ -n "$(find "$f" -mtime +$KEEP_DAYS 2>/dev/null)" ]; then
      rm -f "$f" && log "pruned: $base"
    fi
  done
}

# 2026-07-30, Max's call, in his words: "open the floodgates… SAVE ALL THE DATA…
# this is executive decision by me to maintain all the data long term."
#
# So nothing is pruned any more. `prune_dir` above is kept, unused, because the
# decision it encodes (keep the first dump of each month) is the sane fallback if
# storage ever does become a problem — reinstating it is uncommenting two lines,
# and rewriting it from scratch under pressure is how you delete the wrong file.
#
# Room to run: both Pis are 117G with 96G free, so the SD cards are not the
# constraint. The one to watch is Google Drive — roughly 18MB a day, about 6.5GB
# in the first year and growing as the database does. A free Google account is
# 15GB TOTAL including Gmail and Photos, so this fills it in well under two years
# if that is the plan in force.
#
# prune_dir "$LOCAL"
# prune_dir "$DRIVE"

# Half-written temp files are still cleaned up — those are junk, not archives.
find "$LOCAL" -name ".${HOST}-${DB}-*.tmp" -mmin +120 -delete

# Third copy: the external drive. It is portable and usually unplugged, so this
# never fails the backup — the sync script reports `standby` when the drive is
# absent and catches up automatically the moment it is plugged in (launchd
# StartOnMount). Three copies, two kinds of media, one off-site.
bash "$HOME/bin/sync-archives-external.sh" >/dev/null 2>&1 || true

log "done"
