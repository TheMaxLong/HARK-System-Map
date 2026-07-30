#!/bin/bash
# failover-probe.sh — one JSON line describing failover readiness.
#
# READ-ONLY. Nothing is created, modified, or deleted on either Pi.
#
# Deliberately cheap: one bounded query per run, called every 15 min by the
# widget. The 2s-polling flux-widget is what drove anderson-hub to 79C in July
# (six seq-scans of the unindexed 64MB readings table per call) — do not lower
# the widget's refreshFrequency without adding a created_at index first.

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Where the Mac keeps the off-site archive. Override if yours lives elsewhere:
#   export HARK_ARCHIVE_DIR="$HOME/path/to/archives"
# 2026-07-30: this said `facility-archive`. The folder is `facility-archives`.
# One missing letter, and the widget had been showing a red "folder missing" for
# days while 16 archives sat in the real folder. It was written off as cosmetic.
# It was a typo.
ARCHIVE_DIR="${HARK_ARCHIVE_DIR:-$HOME/facility-archives}"

# Where the assurance prover leaves its verdicts. The widget reads that summary
# rather than re-deriving it, so the dot on screen and the thing that actually
# checks your backups can never disagree.
ASSURE_SUMMARY="${ASSURE_SUMMARY:-$HOME/facility-assurance/last-run.txt}"
ARCHIVE_GLOB="hub-backup-fluxuum-*.sql.gz"

SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"

# ---------- anderson-hub (primary) ----------
A_UP=down
A_LAST="--"
A_AGE=-1

if $SSH anderson-hub true 2>/dev/null; then
  A_UP=up
  # Single query returns both the clock time and its age, so this is one scan.
  ROW=$($SSH anderson-hub "timeout 20 sudo -u postgres psql -tAX -F'|' -d fluxuum \
    -c \"select to_char(max(created_at),'MM-DD HH24:MI'), \
       coalesce(extract(epoch from now()-max(created_at))::int,-1) from readings;\"" 2>/dev/null)
  if [ -n "$ROW" ]; then
    A_LAST="${ROW%%|*}"
    A_AGE="${ROW##*|}"
    case "$A_AGE" in ''|*[!0-9-]*) A_AGE=-1 ;; esac
    [ -z "$A_LAST" ] && A_LAST="--"
  fi
fi

# ---------- hub-backup (standby, separate building) ----------
# No sudo here on purpose: the two boxes differ in sudo config, and neither a
# file test nor systemctl's query verbs need it.
#
# Both the marker and the unit state are needed to answer "can this actually
# fire?". The marker alone is not enough — a masked or dead unit cannot promote
# whatever /home/pi/PROMOTED_AT says, and calling that "armed" would be a lie in
# exactly the situation where the answer matters.
B_UP=down
PROMOTED=unknown
W_ACTIVE=unknown
W_ENABLED=unknown

if $SSH hub-backup true 2>/dev/null; then
  B_UP=up
  if $SSH hub-backup 'test -f /home/pi/PROMOTED_AT' 2>/dev/null; then
    PROMOTED=present
  else
    PROMOTED=absent
  fi
  WROW=$($SSH hub-backup 'systemctl is-active failover-watcher.service 2>/dev/null; \
    systemctl is-enabled failover-watcher.service 2>/dev/null' 2>/dev/null)
  W_ACTIVE=$(printf '%s\n' "$WROW" | sed -n 1p | tr -d '[:space:]')
  W_ENABLED=$(printf '%s\n' "$WROW" | sed -n 2p | tr -d '[:space:]')
  [ -z "$W_ACTIVE" ] && W_ACTIVE=unknown
  [ -z "$W_ENABLED" ] && W_ENABLED=unknown
fi

# ---------- off-site archive (local, free) ----------
ARCH_N=0
ARCH_AGE=-1

if [ -d "$ARCHIVE_DIR" ]; then
  # shellcheck disable=SC2086
  ARCH_N=$(ls -1 "$ARCHIVE_DIR"/$ARCHIVE_GLOB 2>/dev/null | wc -l | tr -d ' ')
  NEWEST=$(ls -1t "$ARCHIVE_DIR"/$ARCHIVE_GLOB 2>/dev/null | head -1)
  if [ -n "$NEWEST" ]; then
    ARCH_AGE=$(( ( $(date +%s) - $(stat -f %m "$NEWEST") ) / 3600 ))
  fi
else
  ARCH_N=-1
fi

# ---------- assurance: what the prover last concluded ----------
# Counting words in a text file, deliberately. macOS ships /bin/bash 3.2 and a
# previous version of this widget was rolled back for a shell syntax error, so
# nothing here uses anything newer than 3.2 and there are no nested quotes.
#
# States come from the prover: proven / failed / blocked / unproven / unsupported.
# `blocked` is NOT a failure — it means a check could not look. Keeping them apart
# on screen is the whole point; a red dot that means "I could not see" sends you
# hunting for a problem that does not exist.
AS_PROVEN=0
AS_FAILED=0
AS_BLOCKED=0
AS_RESTORE=none
AS_WHEN=never

if [ -f "$ASSURE_SUMMARY" ]; then
  AS_PROVEN=$(grep -c ' proven '  "$ASSURE_SUMMARY" 2>/dev/null)
  AS_FAILED=$(grep -c ' failed '  "$ASSURE_SUMMARY" 2>/dev/null)
  AS_BLOCKED=$(grep -c ' blocked ' "$ASSURE_SUMMARY" 2>/dev/null)
  # Match the ROW NAME, not the word anywhere in the line. Grepping for
  # "restores" matched five rows, because the integrity checks carry the note
  # "does NOT prove it restores" — and five states joined by newlines produced
  # invalid JSON and a blank widget. Anchor on the first field, take one.
  AS_RESTORE=$(awk '$1 ~ /-restores$/ {print $2; exit}' "$ASSURE_SUMMARY" 2>/dev/null)
  [ -z "$AS_RESTORE" ] && AS_RESTORE=none
  AS_WHEN=$(stat -f %Sm -t '%m-%d %H:%M' "$ASSURE_SUMMARY" 2>/dev/null)
  [ -z "$AS_WHEN" ] && AS_WHEN=never
fi
[ -z "$AS_PROVEN" ] && AS_PROVEN=0
[ -z "$AS_FAILED" ] && AS_FAILED=0
[ -z "$AS_BLOCKED" ] && AS_BLOCKED=0

# ---------- drills: can the alarms still go red? ----------
# This line qualifies every line above it. "19 proven" is only worth reading if
# the checks that produced it are still capable of failing — and on 2026-07-29
# every green tick on this machine came from a check that could not.
DR_STATE=never
DR_PASS=0
DR_MISS=0
DR_RECEIPT="$HOME/Library/Logs/facility-assurance-drills-last.txt"
if [ -f "$DR_RECEIPT" ]; then
  DR_STATE=$(sed -n 's/^state=//p' "$DR_RECEIPT" | head -1)
  DR_PASS=$(sed -n 's/^passed=//p' "$DR_RECEIPT" | head -1)
  DR_MISS=$(sed -n 's/^missed=//p' "$DR_RECEIPT" | head -1)
fi
[ -z "$DR_STATE" ] && DR_STATE=never
[ -z "$DR_PASS" ] && DR_PASS=0
[ -z "$DR_MISS" ] && DR_MISS=0

printf '{"anderson":{"up":"%s","last":"%s","age":%s},"backup":{"up":"%s"},"promoted":"%s","watcher":{"active":"%s","enabled":"%s"},"archive":{"count":%s,"age_h":%s},"assurance":{"proven":%s,"failed":%s,"blocked":%s,"restore":"%s","when":"%s"},"drills":{"state":"%s","passed":%s,"missed":%s},"checked":"%s"}\n' \
  "$A_UP" "$A_LAST" "${A_AGE:--1}" \
  "$B_UP" "$PROMOTED" "$W_ACTIVE" "$W_ENABLED" \
  "${ARCH_N:--1}" "${ARCH_AGE:--1}" \
  "$AS_PROVEN" "$AS_FAILED" "$AS_BLOCKED" "$AS_RESTORE" "$AS_WHEN" \
  "$DR_STATE" "$DR_PASS" "$DR_MISS" \
  "$(date '+%H:%M')"
