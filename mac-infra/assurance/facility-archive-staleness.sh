#!/bin/bash
# Monitor off-site backup freshness. Alert if stale (>36h old).
#
# Why this exists: 2026-07-26 the off-site backup of facility-archives silently
# failed. For 3 days nobody noticed. During that window a production DB was dropped
# and restored; the off-site copy was 3 days old at the worst moment. The failure
# was recoverable. The SILENCE was the disaster.
#
# Separately, on 2026-07-29 a facility Pi stopped collecting readings at 11:02
# and it went unnoticed for hours. This monitor exists to make dead backups
# impossible to miss.
#
# Design notes:
#  - Runs daily at 09:00 Pacific via launchd.
#  - If fresh (<=36h), exits quietly with one OK log line (no alert).
#  - If stale (>36h), sends an ntfy alert with facts only: filename, age, size.
#  - Handles missing directory, empty directory, and .tmp files.
#  - All times shown to Max are Pacific, never UTC.
#  - Supports DRY_RUN=1 for testing (prints curl cmd, does not send).
#  - Logs to ~/Library/Logs/ (NOT ~/Documents/, which triggers launchd EX_CONFIG).
#
# Created 2026-07-29.

set -u

ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/facility-archives}"

# 2026-07-30: the 09:00 run cried "Facility Archive Empty" while a 17MB backup
# from 03:00 sat in that exact folder. The folder was never wrong — macOS will
# let a scheduled job stat a directory under ~/Documents and then hand it back an
# EMPTY listing, because that path is protected and launchd has no permission to
# enumerate it. Run by hand from a terminal it works; run by launchd it does not,
# which is why this looked impossible to reproduce.
#
# The backup script writes the same file to two places. The second one lives
# under ~/Library, which is not protected, so a scheduled job CAN read it. Check
# both and take the newest that is actually visible. Only shout when NEITHER can
# be read — the point of this alarm is to notice a dead backup, and an alarm that
# fires every morning for the wrong reason is one nobody reads by Friday.
ARCHIVE_DIR_ALT="${ARCHIVE_DIR_ALT:-$HOME/Library/CloudStorage/GoogleDrive-max2k03@gmail.com/My Drive/facility-archives}"
LOG_FILE="$HOME/Library/Logs/facility-archive-staleness.log"
# The alert topic is a SECRET — on ntfy.sh the topic name IS the password, and
# anyone holding it can both read every alert and send fake ones. It lives in
# ~/.config/facility-assurance/ntfy-topic (mode 600) and NEVER in a file that
# could be committed. HARK-System-Map is a public repository; this script is
# mirrored there.
#
# No default. If the topic file is missing, alerting is disabled loudly rather
# than silently sending nowhere.
NTFY_TOPIC="${NTFY_TOPIC:-$(cat "$HOME/.config/facility-assurance/ntfy-topic" 2>/dev/null)}"
NTFY_URL="https://ntfy.sh/$NTFY_TOPIC"
STALE_HOURS=36
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$HOME/Library/Logs"

log() {
  # ISO-8601 timestamp, always Pacific.
  # The previous version took `date -u` (UTC) and re-parsed it as if it were
  # local, which printed UTC digits stamped with a -0700 offset — 7 hours wrong
  # AND mislabelled, which is worse than plain UTC because it looks correct.
  # TZ is pinned explicitly so this stays Pacific even if the Mac's zone changes.
  local ts
  ts=$(TZ=America/Los_Angeles date +"%Y-%m-%dT%H:%M:%S%z")
  printf "%s %s\n" "$ts" "$*" >> "$LOG_FILE"
}

alert() {
  local title="$1"
  local msg="$2"

  local cmd=(
    curl
    -s
    -m 10
    -H "Title: $title"
    -H "Priority: high"
    -H "Tags: warning"
    -d "$msg"
    "$NTFY_URL"
  )

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN: would send alert"
    printf "%s\n" "${cmd[@]}"
  else
    "${cmd[@]}"
    log "ALERT sent: $title"
  fi
}

# Both copies are written by the same backup run, so either one answers the
# question "is the backup fresh?". Take the newest file visible in either.
newest=""
newest_epoch=0
found_dir=""
seen_any_dir=0

for dir in "$ARCHIVE_DIR" "$ARCHIVE_DIR_ALT"; do
  [ -d "$dir" ] || { log "note: $dir does not exist"; continue; }
  seen_any_dir=1
  cand=$(ls -t "$dir"/hub-backup-fluxuum-*.sql.gz 2>/dev/null | grep -v DEEPARCHIVE | grep -v '\.tmp$' | head -1)
  [ -n "$cand" ] || { log "note: nothing readable in $dir"; continue; }
  cand_epoch=$(stat -f %m "$cand" 2>/dev/null || stat -c %Y "$cand" 2>/dev/null || echo 0)
  if [ "$cand_epoch" -gt "$newest_epoch" ]; then
    newest="$cand"; newest_epoch="$cand_epoch"; found_dir="$dir"
  fi
done

if [ "$seen_any_dir" = "0" ]; then
  log "ERROR: no archive directory exists (checked $ARCHIVE_DIR and $ARCHIVE_DIR_ALT)"
  alert "Facility Archive Missing" "Neither archive folder was found. Checked: $ARCHIVE_DIR and $ARCHIVE_DIR_ALT"
  exit 1
fi

# Both archive folders are protected paths, so a launchd job can stat them and
# still get an empty listing. When that happens, fall back to the receipt the
# backup script writes into ~/Library/Logs — a place a scheduled job CAN read.
# The receipt is only written after a dump passes verification, so its age is a
# faithful answer to "when did a good backup last exist?".
RECEIPT="$HOME/Library/Logs/facility-archive-last.txt"
if [ -z "$newest" ] && [ -r "$RECEIPT" ]; then
  r_epoch=$(sed -n 's/^epoch=//p' "$RECEIPT" | head -1)
  r_name=$(sed -n 's/^name=//p' "$RECEIPT" | head -1)
  r_size=$(sed -n 's/^size=//p' "$RECEIPT" | head -1)
  if [ -n "${r_epoch:-}" ]; then
    newest_epoch="$r_epoch"
    newest="RECEIPT:${r_name:-unknown}"
    found_dir="$RECEIPT"
    log "folders unreadable by this job — using backup receipt instead (${r_name:-unknown}, ${r_size:-?})"
  fi
fi

[ -n "$newest" ] && log "using $found_dir"

# `newest` was already chosen above, across both archive folders.

# 2026-07-30: "no matching files" and "I cannot see inside this folder" are NOT
# the same thing, and this script used to report both as "Facility Archive
# Empty" -- the most alarming message it has. That is exactly what happened at
# 09:00 today: launchd ran it, it could stat the directory (so -d and -r both
# passed) but got an empty listing, and it pushed "No backup files found" while
# a 17MB backup from 03:00 was sitting right there. A monitor that cries wolf
# gets ignored, and then it is worse than no monitor at all.
#
# macOS lets a process stat a protected directory but hands back an empty
# listing when it lacks permission to enumerate it. So: a directory that
# contains ZERO entries of any kind is the signature of that, not of a genuinely
# empty archive -- a real archive folder always has something in it. Say
# "cannot verify" in that case and keep the alarming wording for the real thing.
if [ -z "$newest" ]; then
  total_entries=$(ls -A "$ARCHIVE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$total_entries" = "0" ]; then
    log "ERROR: cannot enumerate $ARCHIVE_DIR (0 entries visible) -- permission, not proof of absence"
    alert "Facility Archive UNVERIFIABLE" \
      "Could not read the contents of $ARCHIVE_DIR. This is NOT proof the backups are gone -- most likely this job lacks permission to list that folder. Check by hand before acting."
    exit 1
  fi
  log "ERROR: no backup files found in $ARCHIVE_DIR ($total_entries other entries visible)"
  alert "Facility Archive Empty" "No hub-backup-fluxuum-*.sql.gz files found (folder has $total_entries other entries)."
  exit 1
fi

# `newest` may be a real path, or the marker "RECEIPT:<name>" when the folders
# were unreadable. `newest_epoch` is already correct in both cases — do not stat
# a marker.
case "$newest" in
  RECEIPT:*)
    filename="${newest#RECEIPT:}"
    filesize="${r_size:-unknown}"
    ;;
  *)
    filename=$(basename "$newest")
    filesize=$(ls -lh "$newest" | awk '{print $5}')
    ;;
esac

# Compute age in hours.
now_epoch=$(date +%s)
file_epoch="$newest_epoch"
age_seconds=$((now_epoch - file_epoch))
age_hours=$((age_seconds / 3600))

log "check: $filename age=$age_hours hours size=$filesize"

rc=0
if [ "$age_hours" -gt "$STALE_HOURS" ]; then
  msg="Newest fluxuum backup is $age_hours hours old (limit: $STALE_HOURS). File: $filename, Size: $filesize"
  alert "Facility Archive Stale" "$msg"
  log "STALE: $filename is $age_hours hours old (>$STALE_HOURS threshold)"
  rc=1
else
  log "OK: $filename is fresh ($age_hours hours <= $STALE_HOURS)"
fi

# --- the other three databases, added 2026-07-30 ---------------------------------
# As of today FOUR databases are archived: fluxuum and cannamax on each of
# hub-backup and anderson-hub. The block above covers hub-backup/fluxuum via its
# folder-or-receipt path. The rest are checked by receipt only, for the same reason:
# a launchd job cannot list ~/Documents, so the folder is not a place it can ask.
#
# Every one of them is checked. A backup nobody watches is how fluxuum's went three
# days dead in July without anyone noticing, and there is no reason the other three
# would fail more loudly.
#
# Format: <label>|<receipt path>
OTHER_BACKUPS="
hub-backup cannamax|$HOME/Library/Logs/facility-archive-cannamax-last.txt
anderson-hub fluxuum|$HOME/Library/Logs/facility-archive-anderson-hub-fluxuum-last.txt
anderson-hub cannamax|$HOME/Library/Logs/facility-archive-anderson-hub-cannamax-last.txt
"

printf '%s\n' "$OTHER_BACKUPS" | while IFS='|' read -r label receipt; do
  [ -n "$label" ] || continue
  if [ ! -r "$receipt" ]; then
    log "ERROR: no backup receipt for $label at $receipt"
    alert "Backup Missing: $label" \
      "No record of a $label backup ever completing. Expected a receipt at $receipt."
    continue
  fi
  b_epoch=$(sed -n 's/^epoch=//p' "$receipt" | head -1)
  b_name=$(sed -n 's/^name=//p' "$receipt" | head -1)
  b_size=$(sed -n 's/^size=//p' "$receipt" | head -1)
  if [ -z "${b_epoch:-}" ]; then
    log "ERROR: receipt for $label is unreadable or has no epoch"
    alert "Backup Unverifiable: $label" "The receipt exists but could not be read: $receipt"
    continue
  fi
  b_age=$(( (now_epoch - b_epoch) / 3600 ))
  log "check: ${b_name:-$label} age=$b_age hours size=${b_size:-?}"
  if [ "$b_age" -gt "$STALE_HOURS" ]; then
    alert "Backup Stale: $label" \
      "Newest $label backup is $b_age hours old (limit: $STALE_HOURS). File: ${b_name:-unknown}, Size: ${b_size:-unknown}"
    log "STALE: ${b_name:-$label} is $b_age hours old (>$STALE_HOURS threshold)"
  else
    log "OK: ${b_name:-$label} is fresh ($b_age hours <= $STALE_HOURS)"
  fi
done

# NOTE: the loop above runs in a subshell (it is on the right of a pipe), so an
# `rc=1` set inside it would NOT survive out here. Exit status therefore reflects
# the hub-backup/fluxuum check only — the alerts are what matter for the other
# three, and those are sent from inside the loop where they belong.
exit $rc
