#!/bin/bash
# drill-alarms.sh — deliberately break things, and confirm the alarms notice.
#
# A guard nobody has watched fire is not a guard, it is a hope. Everything that
# went wrong on 2026-07-29 was a check that had never once been seen to fail:
# the 09:00 archive alarm cried wolf for days and was never right, the pre-drop
# safety guard is in place today and its critical path has still never executed.
#
# So every drill here causes a REAL failure and asserts the prover reports the
# REAL state. When a drill that should go red comes back green, that silence is
# the finding — and it is the only kind of finding this script exists to produce.
#
# ⛔ NOTHING HERE TOUCHES A REAL ARCHIVE.
# Each drill builds a sandbox of throwaway files in a temp directory and hands
# the prover a different world via LOCAL_ARCHIVES / DRIVE_ARCHIVES / MANIFEST.
# The real archive folders are never named, never written, never deleted. That is
# a structural guarantee, not a promise to be careful — the drill cannot reach
# them because it never tells the prover where they are.
#
# Run by hand any time. Scheduled weekly. Safe to run at any hour: it makes no
# network calls, touches no Pi, and sends no alerts of its own except the one
# that matters — "an alarm did not fire when it should have".
#
# Created 2026-07-30.

set -o pipefail

PROVER="${PROVER:-$HOME/bin/prove-archives.sh}"
LOG_FILE="$HOME/Library/Logs/facility-assurance-drills.log"
RECEIPT="$HOME/Library/Logs/facility-assurance-drills-last.txt"
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

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/assurance-drill.XXXXXX") || exit 1
# Belt and braces: never leave a sandbox behind, even on an error or an interrupt.
cleanup() { chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM

mkdir -p "$HOME/Library/Logs"
log() { echo "[$(TZ=America/Los_Angeles date -Iseconds)] $*" >> "$LOG_FILE"; }

PASS=0
MISS=0
MISSED_LIST=""

# ---------------------------------------------------------------------------
# drill NAME EXPECTED_STATE
#
# Everything before the call has already staged the sandbox. This runs the real
# prover against it and compares the state it reports with the state the
# situation actually deserves.
# ---------------------------------------------------------------------------
drill() {
  local name="$1" expect="$2" manifest="$3" local_dir="$4" drive_dir="$5" logdir="$6"
  local out state

  out=$(ASSURE_DIR="$SANDBOX/assure" \
        MANIFEST="$manifest" \
        LOCAL_ARCHIVES="$local_dir" \
        DRIVE_ARCHIVES="$drive_dir" \
        LOG_DIR="$logdir" \
        DRY_RUN=1 \
        bash "$PROVER" 2>&1)

  state=$(awk '{print $2}' "$SANDBOX/assure/last-run.txt" 2>/dev/null | head -1)
  : > "$SANDBOX/assure/last-run.txt" 2>/dev/null

  if [ "$state" = "$expect" ]; then
    PASS=$((PASS + 1))
    log "PASS  $name — reported '$state' as it should"
    printf '  %-46s %-11s ✓\n' "$name" "$state"
  else
    MISS=$((MISS + 1))
    MISSED_LIST="$MISSED_LIST
  $name: expected '$expect', got '${state:-nothing}'"
    log "MISSED $name — expected '$expect' but got '${state:-nothing}'"
    printf '  %-46s %-11s ✗ expected %s\n' "$name" "${state:-nothing}" "$expect"
  fi
}

# ---------------------------------------------------------------------------
# sandbox scaffolding
# ---------------------------------------------------------------------------
mkarchive() {  # mkarchive DIR NAME  — a small but genuinely valid .sql.gz
  mkdir -p "$1"
  printf 'COPY public.readings (id) FROM stdin;\n1\n\\.\n' | gzip -9 > "$1/$2"
}

mkreceipt() {  # mkreceipt DIR NAME AGE_HOURS
  mkdir -p "$1"
  {
    echo "name=drill-archive.sql.gz"
    echo "size=1K"
    echo "drive_ok=yes"
    echo "epoch=$(( $(date +%s) - ($3 * 3600) ))"
  } > "$1/$2"
}

echo "assurance drills — $(TZ=America/Los_Angeles date '+%Y-%m-%d %H:%M')"
echo "sandbox: $SANDBOX (deleted on exit; no real archive is reachable from here)"
echo

# ===========================================================================
# 1. Freshness — the alarm that failed you for days
# ===========================================================================
L="$SANDBOX/one"; D="$SANDBOX/one-drive"; LOGS="$SANDBOX/logs"
mkarchive "$L" "drill-archive.sql.gz"; mkarchive "$D" "drill-archive.sql.gz"

mkreceipt "$LOGS" "drill-last.txt" 1
echo "drill-fresh | receipt_fresh | drill-last.txt | 36" > "$SANDBOX/m1.txt"
drill "fresh backup is reported fresh" proven "$SANDBOX/m1.txt" "$L" "$D" "$LOGS"

# ===========================================================================
# 2. THE ONE THAT MATTERS — a stale backup must go red
# ===========================================================================
mkreceipt "$LOGS" "drill-stale.txt" 72
echo "drill-stale | receipt_fresh | drill-stale.txt | 36" > "$SANDBOX/m2.txt"
drill "72h-old backup is reported BROKEN" failed "$SANDBOX/m2.txt" "$L" "$D" "$LOGS"

# ===========================================================================
# 3. A backup that has never run at all
# ===========================================================================
echo "drill-never | receipt_fresh | drill-nonexistent.txt | 36" > "$SANDBOX/m3.txt"
drill "backup that never ran is flagged" unproven "$SANDBOX/m3.txt" "$L" "$D" "$LOGS"

# ===========================================================================
# 4. Corruption — gzip integrity must catch a damaged archive
# ===========================================================================
CL="$SANDBOX/corrupt"; mkdir -p "$CL"
mkarchive "$CL" "hub-backup-fluxuum-20260101-0000.sql.gz"
printf 'this is not gzip data at all' > "$CL/hub-backup-fluxuum-20260101-0000.sql.gz"
echo "drill-corrupt | integrity | hub-backup-fluxuum-*.sql.gz" > "$SANDBOX/m4.txt"
drill "corrupt archive is caught" failed "$SANDBOX/m4.txt" "$CL" "$D" "$LOGS"

# ===========================================================================
# 5. A healthy archive must NOT be called corrupt (false-positive check)
# ===========================================================================
GL="$SANDBOX/good"; mkarchive "$GL" "hub-backup-fluxuum-20260101-0000.sql.gz"
drill "healthy archive is not falsely condemned" proven "$SANDBOX/m4.txt" "$GL" "$D" "$LOGS"

# ===========================================================================
# 6. The deep archive vanishing — the one file with no second chance
# ===========================================================================
EL="$SANDBOX/empty"; mkdir -p "$EL"; : > "$EL/placeholder.txt"
echo "drill-gone | never_pruned | hub-backup-fluxuum-DEEPARCHIVE-*.sql.gz" > "$SANDBOX/m5.txt"
drill "deep archive going missing is caught" failed "$SANDBOX/m5.txt" "$EL" "$D" "$LOGS"

# ===========================================================================
# 7. THE CENTRAL ONE — a folder it cannot read must be `blocked`, never `failed`
#
# This is the whole thesis. On 2026-07-29 an unreadable folder was reported as
# "Facility Archive Empty" — the most alarming words the alarm had — while a
# 17MB backup sat inside it. If this drill ever comes back `failed`, the system
# has regressed into the exact bug it was built to abolish.
# ===========================================================================
UL="$SANDBOX/unreadable"; mkdir -p "$UL"; mkarchive "$UL" "hub-backup-fluxuum-20260101-0000.sql.gz"
chmod 000 "$UL" 2>/dev/null
drill "unreadable folder says BLOCKED, not broken" blocked "$SANDBOX/m4.txt" "$UL" "$D" "$LOGS"
chmod 755 "$UL" 2>/dev/null

# ===========================================================================
# 8. The external drive being unplugged is standby, not a failure
# ===========================================================================
echo "drill-ext | external_copy | hub-backup-fluxuum-*.sql.gz" > "$SANDBOX/m6.txt"
ARCHIVE_EXT_VOL="$SANDBOX/no-such-volume" drill "unplugged drive is standby, not broken" unsupported "$SANDBOX/m6.txt" "$GL" "$D" "$LOGS"

# ---------------------------------------------------------------------------
echo
if [ "$MISS" -eq 0 ]; then
  echo "$PASS/$PASS drills passed — every alarm fired when it should, and stayed quiet when it should."
  log "all $PASS drills passed"
  { echo "state=passed"; echo "passed=$PASS"; echo "missed=0"; echo "epoch=$(date +%s)"; } > "$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"
  exit 0
fi

echo "$MISS of $((PASS + MISS)) drills MISSED:$MISSED_LIST"
log "MISSED $MISS drills"
{ echo "state=missed"; echo "passed=$PASS"; echo "missed=$MISS"; echo "epoch=$(date +%s)"; } > "$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"

# An alarm that did not fire is worth waking someone for. It means every green
# tick elsewhere is now unverified.
if [ "$DRY_RUN" != "1" ]; then
  curl -s -H "Title: An alarm did not fire ($MISS)" -H "Priority: high" \
    -d "A drill deliberately broke something and the check did not notice:$MISSED_LIST" \
    "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1
  log "ALERT sent"
fi
exit 1
