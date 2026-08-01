#!/bin/bash
# prove-archives.sh — checks every promise in the manifest and keeps the receipt.
#
# Why this exists: on 2026-07-29 a Pi died for eight hours. The outage was
# ordinary. What made it expensive was that every system around it reported a
# health it had never verified — an alarm said the archives were gone while a
# 17MB backup sat in the folder, a deploy exited 0 having written nothing, a
# watcher called the standby "Anderson hub" for two months.
#
# So this is not more monitoring. There was monitoring and it lied.
#
# TWO RULES, both bought with real failures:
#
#   1. A check reports one of FIVE states, never a boolean.
#      Taken from alexandria's docs/dossiers/*.capabilities.json, where a
#      capability is proven/unproven/blocked/unsupported rather than true/false,
#      because a boolean once produced a false `adapterAvailable: true`.
#
#        proven      checked, and good, and the evidence is stored
#        failed      checked, and genuinely bad  → this is the alarm
#        blocked     TRIED TO CHECK AND COULD NOT SEE → fix the checker
#        unproven    nothing has ever checked this   → coverage hole
#        unsupported cannot apply here, by design
#
#      `failed` is the one alexandria does not need — a capability is proven or
#      it is not, but a health check can be actively bad. Everything else is
#      its vocabulary unchanged.
#
#      `blocked` is the whole point. The 09:00 alarm should have said
#      "cannot list that folder", not "the backups are gone". It fired every
#      morning for days and was never once right.
#
#   2. Every verdict stores the command and its raw output.
#      "identical checksums on both Pis" was written down and false. "No code
#      tree drift" was claimed off a single spot-check and was false. Both would
#      have been caught in seconds if the claim had carried its evidence.
#
# Reads : ~/facility-assurance/manifest.txt
# Writes: ~/facility-assurance/evidence/<id>.json   (one receipt per promise)
#         ~/facility-assurance/last-run.txt         (summary a scheduler can read)
# Alerts: only on failed / blocked, and never for `unproven` — a coverage hole is
#         a thing to fix in daylight, not at 03:00.
#
# Created 2026-07-30.

set -o pipefail

ASSURE_DIR="${ASSURE_DIR:-$HOME/facility-assurance}"
MANIFEST="${MANIFEST:-$ASSURE_DIR/manifest.txt}"
EVIDENCE="$ASSURE_DIR/evidence"
SUMMARY="$ASSURE_DIR/last-run.txt"
# Where the backup jobs leave their receipts. Overridable for the same reason as
# the archive paths: a drill hands the prover a sandbox of fake receipts so it can
# never read — or be fooled by — a real one.
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs}"
LOG_FILE="${LOG_FILE:-$HOME/Library/Logs/facility-assurance.log}"

# Overridable so the drills can point this at a sandbox of throwaway copies.
# A drill must never be able to touch a real archive, and the safest way to
# guarantee that is for the drill to hand the prover a different world entirely
# rather than for the prover to be told "this one is only a test".
LOCAL_ARCHIVES="${LOCAL_ARCHIVES:-$HOME/facility-archives}"
DRIVE_ARCHIVES="${DRIVE_ARCHIVES:-$HOME/Library/CloudStorage/GoogleDrive-max2k03@gmail.com/My Drive/facility-archives}"

# The alert topic is a SECRET — on ntfy.sh the topic name IS the password, and
# anyone holding it can both read every alert and send fake ones. It lives in
# ~/.config/facility-assurance/ntfy-topic (mode 600) and NEVER in a file that
# could be committed. HARK-System-Map is a public repository; this script is
# mirrored there.
#
# No default. If the topic file is missing, alerting is disabled loudly rather
# than silently sending nowhere.
NTFY_TOPIC="${NTFY_TOPIC:-$(cat "$HOME/.config/facility-assurance/ntfy-topic" 2>/dev/null)}"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$EVIDENCE" "$LOG_DIR"

log() { echo "[$(TZ=America/Los_Angeles date -Iseconds)] $*" | tee -a "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# record ID STATE PROVENANCE NOTE COMMAND OUTPUT
#
# provenance says HOW we know, copied from the same alexandria file:
#   probe-confirmed  we ran something and read the result
#   documented       someone asserted it
# A documented claim is not evidence. Most of what went wrong was `documented`
# wearing a green tick.
# ---------------------------------------------------------------------------
record() {
  local id="$1" state="$2" prov="$3" note="$4" cmd="$5" out="$6"
  local esc_note esc_cmd esc_out
  esc_note=$(printf '%s' "$note" | sed 's/\\/\\\\/g; s/"/\\"/g')
  esc_cmd=$(printf '%s'  "$cmd"  | sed 's/\\/\\\\/g; s/"/\\"/g')
  esc_out=$(printf '%s'  "$out"  | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g' | cut -c1-800)
  cat > "$EVIDENCE/$id.json" <<JSON
{
  "id": "$id",
  "state": "$state",
  "provenance": "$prov",
  "note": "$esc_note",
  "command": "$esc_cmd",
  "output": "$esc_out",
  "checked_at": "$(TZ=America/Los_Angeles date -Iseconds)"
}
JSON
  printf '%-32s %-11s %s\n' "$id" "$state" "$note" >> "$SUMMARY"
  log "$id: $state — $note"
}

alert() {
  local title="$1" body="$2"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: would alert — $title: $body"; return; fi
  curl -s -H "Title: $title" -H "Priority: high" -d "$body" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1
  log "ALERT sent: $title"
}

# ---------------------------------------------------------------------------
# A folder we cannot enumerate is BLOCKED, never empty.
#
# macOS lets a process stat a directory under ~/Documents and then hands it an
# EMPTY listing when it lacks permission to list it. A directory holding zero
# entries of ANY kind is the signature of that, not of a genuinely empty folder —
# a real archive folder always has something in it.
# ---------------------------------------------------------------------------
dir_readable() {
  local d="$1"
  [ -d "$d" ] || return 2                       # 2 = not there at all
  [ "$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')" != "0" ] || return 1  # 1 = cannot see
  return 0
}

newest_in() {  # newest_in DIR GLOB
  ls -t "$1"/$2 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------

check_receipt_fresh() {   # id, receipt filename, max age hours
  local id="$1" rname="$2" maxh="$3"
  local r="$LOG_DIR/$rname"
  local cmd="cat $r"
  if [ ! -r "$r" ]; then
    record "$id" unproven documented "no backup receipt has ever been written at $r" "$cmd" "(missing)"
    return
  fi
  local out epoch name age
  out=$(cat "$r" 2>&1)
  epoch=$(sed -n 's/^epoch=//p' "$r" | head -1)
  name=$(sed -n 's/^name=//p'  "$r" | head -1)
  if [ -z "${epoch:-}" ]; then
    record "$id" blocked probe-confirmed "receipt exists but has no timestamp in it — cannot judge freshness" "$cmd" "$out"
    return
  fi
  age=$(( ( $(date +%s) - epoch ) / 3600 ))
  if [ "$age" -gt "$maxh" ]; then
    record "$id" failed probe-confirmed "newest backup is ${age}h old, limit ${maxh}h (${name:-unknown})" "$cmd" "$out"
  else
    record "$id" proven probe-confirmed "${age}h old, within ${maxh}h (${name:-unknown})" "$cmd" "$out"
  fi
}

check_file_pair() {       # id, glob — must exist locally AND on Drive
  local id="$1" glob="$2"
  local cmd="ls $LOCAL_ARCHIVES/$glob and Drive copy"
  dir_readable "$LOCAL_ARCHIVES"; local lr=$?
  dir_readable "$DRIVE_ARCHIVES"; local dr=$?

  # The local folder moved out of ~/Documents so a scheduled job can read it.
  # Google Drive cannot move — ~/Library/CloudStorage is protected the same way
  # and there is no equivalent escape. So when the local side IS readable and only
  # Drive is not, fall back to the backup job's own receipt: it records whether the
  # Drive copy succeeded, and it was written by a process that could see. Same
  # trick that fixed the 09:00 alarm — ask the thing that was there at the time.
  if [ $lr -eq 0 ] && [ $dr -eq 1 ]; then
    # THIS database's own receipt, named in the manifest — not just any receipt.
    # A receipt from a different database says nothing about this archive, and
    # accepting one would be precisely the kind of "close enough" that produced
    # the false green this system exists to abolish.
    local rname="$3" drive_line
    if [ -z "$rname" ]; then
      record "$id" blocked probe-confirmed "cannot list Google Drive from a scheduled job, and this promise names no receipt to fall back on — NOT proof it is missing" "$cmd" "local rc=$lr drive rc=$dr"
      return
    fi
    drive_line=$(sed -n 's/^drive_ok=//p' "$LOG_DIR/$rname" 2>/dev/null | head -1)
    case "$drive_line" in
      yes) record "$id" proven documented "local copy present; the backup job recorded a successful Drive copy in $rname (a scheduled job cannot list Drive itself)" "$cmd" "drive_ok=yes" ;;
      no)  record "$id" failed probe-confirmed "the backup job recorded that the Drive copy FAILED ($rname)" "$cmd" "drive_ok=no" ;;
      *)   record "$id" blocked probe-confirmed "cannot list Google Drive from a scheduled job, and $rname does not yet record whether the Drive copy worked — NOT proof it is missing" "$cmd" "drive_ok=${drive_line:-absent}" ;;
    esac
    return
  fi

  if [ $lr -eq 1 ] || [ $dr -eq 1 ]; then
    record "$id" blocked probe-confirmed "cannot list an archive folder from this context — permission, NOT proof the files are gone" "$cmd" "local rc=$lr drive rc=$dr"
    return
  fi
  if [ $lr -eq 2 ] || [ $dr -eq 2 ]; then
    record "$id" failed probe-confirmed "an archive folder does not exist (local rc=$lr drive rc=$dr)" "$cmd" ""
    return
  fi
  local l d
  l=$(newest_in "$LOCAL_ARCHIVES" "$glob")
  d=$(newest_in "$DRIVE_ARCHIVES" "$glob")
  if [ -z "$l" ] && [ -z "$d" ]; then
    record "$id" failed probe-confirmed "no archive matching $glob in either location" "$cmd" ""
  elif [ -z "$d" ]; then
    record "$id" failed probe-confirmed "exists locally but NOT on Drive — one copy in one building is not off-site" "$cmd" "local=$(basename "$l")"
  elif [ -z "$l" ]; then
    record "$id" failed probe-confirmed "exists on Drive but not locally" "$cmd" "drive=$(basename "$d")"
  else
    record "$id" proven probe-confirmed "in both places (newest $(basename "$l"))" "$cmd" "local=$(basename "$l") drive=$(basename "$d")"
  fi
}

check_never_pruned() {    # id, glob — this file must still exist
  local id="$1" glob="$2"
  local cmd="ls $LOCAL_ARCHIVES/$glob"
  dir_readable "$LOCAL_ARCHIVES"; local lr=$?
  if [ $lr -eq 1 ]; then
    record "$id" blocked probe-confirmed "cannot list the archive folder — permission, not proof of deletion" "$cmd" ""
    return
  fi
  local f
  f=$(newest_in "$LOCAL_ARCHIVES" "$glob")
  if [ -z "$f" ]; then
    record "$id" failed probe-confirmed "GONE — nothing matches $glob, and this file is kept because nothing else holds that period" "$cmd" ""
  else
    record "$id" proven probe-confirmed "present ($(basename "$f"), $(ls -lh "$f" | awk '{print $5}'))" "$cmd" "$(basename "$f")"
  fi
}

check_integrity() {       # id, glob — newest matching archive passes gzip -t
  local id="$1" glob="$2"
  dir_readable "$LOCAL_ARCHIVES"; local lr=$?
  if [ $lr -eq 1 ]; then
    record "$id" blocked probe-confirmed "cannot list the archive folder" "gzip -t" ""
    return
  fi
  local f
  f=$(newest_in "$LOCAL_ARCHIVES" "$glob")
  if [ -z "$f" ]; then
    record "$id" failed probe-confirmed "no archive matching $glob to test" "gzip -t" ""
    return
  fi
  local out
  out=$(gzip -t "$f" 2>&1)
  if [ $? -eq 0 ]; then
    record "$id" proven probe-confirmed "not truncated ($(basename "$f")) — note this does NOT prove it restores" "gzip -t $(basename "$f")" "ok"
  else
    record "$id" failed probe-confirmed "CORRUPT: $(basename "$f")" "gzip -t $(basename "$f")" "$out"
  fi
}

check_external_copy() {   # id, glob — a copy exists on the external drive
  local id="$1" glob="$2"
  local ext_vol="${ARCHIVE_EXT_VOL:-/Volumes/Seagate Portable Drive}"
  local ext="$ext_vol/facility-archives"

  # Unplugged is NOT a failure. The drive is portable and spends most of its life
  # in a drawer; it catches up automatically on mount. Reported as `unsupported`
  # — the check does not apply while the drive is absent — so it can never be
  # mistaken for a missing backup, and never nags.
  if [ ! -d "$ext_vol" ]; then
    record "$id" unsupported probe-confirmed "external drive not connected — standby, it syncs automatically when plugged in" "ls $ext_vol" "(absent)"
    return
  fi
  dir_readable "$LOCAL_ARCHIVES"; local lr=$?
  if [ $lr -eq 1 ]; then
    record "$id" blocked probe-confirmed "cannot list the local archive folder, so nothing to compare against" "ls $LOCAL_ARCHIVES" ""
    return
  fi
  local l b
  l=$(newest_in "$LOCAL_ARCHIVES" "$glob")
  if [ -z "$l" ]; then
    record "$id" failed probe-confirmed "no local archive matching $glob to copy" "ls" ""
    return
  fi
  b=$(basename "$l")
  if [ ! -f "$ext/$b" ]; then
    record "$id" failed probe-confirmed "newest archive $b is NOT on the external drive" "ls $ext/$b" "(missing)"
    return
  fi
  # Present is not the same as correct — but "I could not read it" is not the same
  # as "it differs" either, and that distinction is the whole point of this file.
  #
  # macOS protects REMOVABLE VOLUMES as well as ~/Documents. Under launchd, md5 on
  # the external copy returns an empty string, and comparing empty against a real
  # checksum reported all five archives as DIFFERING when every one of them
  # matched. A false red about backups is the worst possible false alarm, and this
  # is the third time today the same confusion has appeared in different clothes.
  local ml me
  ml=$(md5 -q "$l" 2>/dev/null)
  me=$(md5 -q "$ext/$b" 2>/dev/null)
  if [ -z "$me" ] || [ -z "$ml" ]; then
    record "$id" blocked probe-confirmed "cannot read a copy to compare it (removable volumes are protected from scheduled jobs) — this says NOTHING about whether they match" "md5 compare" "local=${ml:-unreadable} ext=${me:-unreadable}"
    return
  fi
  if [ "$ml" = "$me" ]; then
    record "$id" proven probe-confirmed "on the external drive and byte-identical ($b)" "md5 compare" "match"
  else
    record "$id" failed probe-confirmed "copy on the external drive DIFFERS from the local one ($b)" "md5 compare" "local=$ml ext=$me"
  fi
}

check_restore_drill() {   # id, glob — restore into a disposable database, read a row back
  local id="$1" glob="$2"
  # Deliberately uses a throwaway container. It touches no Pi, no live database,
  # and nothing in the archive folder is modified.
  if ! command -v docker >/dev/null 2>&1; then
    record "$id" blocked documented "no docker on this machine — cannot restore anywhere safe. Unblocker: install Docker, or point this at a scratch Postgres." "docker" ""
    return
  fi
  if ! docker info >/dev/null 2>&1; then
    record "$id" blocked probe-confirmed "docker is installed but not running, so no restore was attempted — this is NOT a statement about the backup. Unblocker: start Docker Desktop." "docker info" "daemon unreachable"
    return
  fi
  # Ask whether we can SEE the folder before concluding anything about what is
  # in it. Missing this is how the first scheduled run of this very script
  # reported "no archive to restore" when the truth was "not allowed to look" —
  # the exact confusion the rest of this file exists to prevent.
  dir_readable "$LOCAL_ARCHIVES"; local lr=$?
  if [ $lr -eq 1 ]; then
    record "$id" blocked probe-confirmed "cannot list the archive folder from this context — no restore attempted, and this says NOTHING about the backup" "ls $LOCAL_ARCHIVES" ""
    return
  fi
  if [ $lr -eq 2 ]; then
    record "$id" failed probe-confirmed "the archive folder does not exist at $LOCAL_ARCHIVES" "ls $LOCAL_ARCHIVES" ""
    return
  fi

  local f
  f=$(newest_in "$LOCAL_ARCHIVES" "$glob")
  [ -n "$f" ] || { record "$id" failed probe-confirmed "no archive matching $glob to restore" "ls" ""; return; }

  local c="assurance-restore-$$"
  local out rows
  out=$(docker run -d --rm --name "$c" -e POSTGRES_PASSWORD=drill -e POSTGRES_DB=drill postgres:16-alpine 2>&1) || {
    record "$id" blocked probe-confirmed "could not start a scratch database container" "docker run postgres:16-alpine" "$out"; return; }

  local ready=0 i
  for i in $(seq 1 30); do
    docker exec "$c" pg_isready -U postgres >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  if [ "$ready" != "1" ]; then
    docker rm -f "$c" >/dev/null 2>&1
    record "$id" blocked probe-confirmed "scratch database never became ready" "pg_isready" ""
    return
  fi

  out=$(gunzip -c "$f" | docker exec -i "$c" psql -U postgres -d drill -v ON_ERROR_STOP=0 2>&1 | tail -5)
  rows=$(docker exec "$c" psql -U postgres -d drill -t -c "SELECT count(*) FROM readings;" 2>&1 | tr -d ' \n')
  docker rm -f "$c" >/dev/null 2>&1

  case "$rows" in
    ''|*[!0-9]*)
      record "$id" failed probe-confirmed "restored but could not read readings back: ${rows:-no answer}" "restore + SELECT count(*) FROM readings" "$out" ;;
    *)
      if [ "$rows" -gt 0 ]; then
        record "$id" proven probe-confirmed "restored $(basename "$f") into a scratch database and read back $rows readings" "restore + SELECT count(*) FROM readings" "rows=$rows"
      else
        record "$id" failed probe-confirmed "restored, but the readings table is EMPTY" "restore + SELECT count(*) FROM readings" "$out"
      fi ;;
  esac
}

# ---------------------------------------------------------------------------
# run every promise in the manifest
# ---------------------------------------------------------------------------
: > "$SUMMARY"
log "run start — manifest $MANIFEST"

if [ ! -r "$MANIFEST" ]; then
  log "FATAL: cannot read manifest at $MANIFEST"
  alert "Assurance manifest missing" "prove-archives.sh cannot read $MANIFEST — nothing was checked."
  exit 1
fi

while IFS='|' read -r id check a1 a2 a3; do
  id=$(echo "$id" | xargs); check=$(echo "$check" | xargs)
  a1=$(echo "${a1:-}" | xargs); a2=$(echo "${a2:-}" | xargs); a3=$(echo "${a3:-}" | xargs)
  [ -z "$id" ] && continue
  case "$id" in \#*) continue ;; esac

  # A promise tagged `monthly` is skipped unless RUN_MONTHLY=1. Restoring is a
  # monthly discipline and must not make the DAILY run depend on Docker being
  # open — otherwise every morning Docker happened to be closed would produce a
  # "could not check" alert that is true, useless, and constant. That is exactly
  # how the 09:00 archive alarm became noise. Skipped, not silently passed: it
  # still gets a receipt saying it was not due.
  if [ "$a2" = "monthly" ] || [ "$a3" = "monthly" ]; then
    if [ "${RUN_MONTHLY:-0}" != "1" ]; then
      record "$id" unsupported documented "monthly check, not due on a daily run — see the monthly job" "(skipped)" ""
      continue
    fi
  fi

  case "$check" in
    receipt_fresh) check_receipt_fresh "$id" "$a1" "$a2" ;;
    file_pair)     check_file_pair     "$id" "$a1" "$a2" ;;
    never_pruned)  check_never_pruned  "$id" "$a1" ;;
    integrity)     check_integrity     "$id" "$a1" ;;
    restore_drill) check_restore_drill "$id" "$a1" ;;
    external_copy) check_external_copy "$id" "$a1" ;;
    *)
      # A promise with no checker behind it is a coverage hole, and saying so is
      # the entire reason the manifest exists.
      record "$id" unproven documented "no checker implemented for '$check' — this promise is NOT being verified" "$check" ""
      ;;
  esac
done < "$MANIFEST"

# ---------------------------------------------------------------------------
# report. failed and blocked both deserve a human; they are different problems.
# ---------------------------------------------------------------------------
n_failed=$(grep -c ' failed '   "$SUMMARY" || true)
n_blocked=$(grep -c ' blocked ' "$SUMMARY" || true)
n_unproven=$(grep -c ' unproven ' "$SUMMARY" || true)
n_proven=$(grep -c ' proven '   "$SUMMARY" || true)

log "run end — proven=$n_proven failed=$n_failed blocked=$n_blocked unproven=$n_unproven"

if [ "${n_failed:-0}" -gt 0 ]; then
  alert "Archive promise broken ($n_failed)" "$(grep ' failed ' "$SUMMARY" | head -5)"
fi
if [ "${n_blocked:-0}" -gt 0 ]; then
  # Deliberately worded so it can never be mistaken for data loss.
  alert "Archive check could not run ($n_blocked)" "This is NOT proof anything is missing — the checker could not look. $(grep ' blocked ' "$SUMMARY" | head -3)"
fi

[ "${n_failed:-0}" -gt 0 ] && exit 1
exit 0
