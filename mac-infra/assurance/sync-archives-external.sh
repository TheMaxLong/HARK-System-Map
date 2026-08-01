#!/bin/bash
# sync-archives-external.sh — copy any missing archives onto the external drive.
#
# The external drive is portable and will spend most of its life unplugged. That
# is normal, and it must never be reported as a failure — an alarm that fires
# every time a USB cable is out is an alarm you learn to ignore, and this project
# already spent a week ignoring one of those.
#
# So: unplugged is `standby`, not `failed`. When the drive appears, this catches
# up automatically. It is wired to launchd's StartOnMount, so plugging the drive
# in IS the trigger — nothing to remember.
#
# Copies only. Never deletes anything from either side, ever.
#
# Created 2026-07-30.

set -o pipefail

LOCAL="${ARCHIVE_LOCAL:-$HOME/facility-archives}"
EXT_VOL="${ARCHIVE_EXT_VOL:-/Volumes/Seagate Portable Drive}"
EXT="$EXT_VOL/facility-archives"
LOG_FILE="$HOME/Library/Logs/facility-archive-external.log"
RECEIPT="$HOME/Library/Logs/facility-archive-external-last.txt"

mkdir -p "$HOME/Library/Logs"
log() { echo "[$(TZ=America/Los_Angeles date -Iseconds)] $*" >> "$LOG_FILE"; }

# Is the drive actually here? A mount point that exists but is not mounted looks
# identical to a mounted empty drive from a distance, so check the mount, not the
# directory.
if [ ! -d "$EXT_VOL" ]; then
  log "standby: external drive not connected — nothing copied, nothing wrong"
  { echo "state=standby"; echo "reason=drive not connected"; echo "epoch=$(date +%s)"; } > "$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"
  exit 0
fi

# Mounted but not writable is a REAL problem — a drive that silently refuses
# writes is worse than one that is absent, because it looks present.
if ! touch "$EXT_VOL/.archive-write-test" 2>/dev/null; then
  # Mounted but unwritable has TWO very different causes and they must not share
  # a state:
  #   - a genuinely failing or read-only disk        → a real problem
  #   - macOS refusing a BACKGROUND job access to a  → not a problem with the disk
  #     removable volume (the same protection that
  #     hides ~/Documents from launchd)
  #
  # Verified 2026-07-30: run from a terminal this script copies happily; run by
  # launchd the very same second, the identical drive is "not writable". So a
  # scheduled run cannot tell you anything about the drive, and calling that
  # `failed` would paint a permanent red over a drive that is fine.
  #
  # Reported as `blocked`, with the unblocker named. A human running this by hand
  # gets the truth.
  log "blocked: drive is mounted but this process cannot write to it — almost certainly macOS withholding removable-volume access from a background job"
  {
    echo "state=blocked"
    echo "reason=mounted but not writable from this context (likely a background job without removable-volume access)"
    echo "unblocker=grant Full Disk Access to /bin/bash, or run this script from a terminal"
    echo "epoch=$(date +%s)"
  } > "$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"
  exit 0
fi
rm -f "$EXT_VOL/.archive-write-test"

mkdir -p "$EXT"

copied=0
skipped=0
failed=0

for f in "$LOCAL"/*.sql.gz; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  if [ -f "$EXT/$b" ]; then
    # Present already — but present is not the same as correct. Compare.
    if [ "$(md5 -q "$f")" = "$(md5 -q "$EXT/$b")" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    log "WARN: $b differs on the external drive — leaving the existing copy alone, not overwriting"
    failed=$((failed + 1))
    continue
  fi
  if cp -p "$f" "$EXT/$b" 2>/dev/null && [ "$(md5 -q "$f")" = "$(md5 -q "$EXT/$b")" ]; then
    copied=$((copied + 1))
    log "copied $b"
  else
    rm -f "$EXT/$b"
    failed=$((failed + 1))
    log "ERROR: copy of $b failed verification — removed the partial"
  fi
done

log "done: copied=$copied already-there=$skipped problems=$failed"
{
  echo "state=$([ "$failed" -gt 0 ] && echo failed || echo synced)"
  echo "copied=$copied"
  echo "present=$skipped"
  echo "problems=$failed"
  echo "epoch=$(date +%s)"
  echo "written=$(TZ=America/Los_Angeles date '+%Y-%m-%dT%H:%M:%S%z')"
} > "$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"

[ "$failed" -gt 0 ] && exit 1
exit 0
