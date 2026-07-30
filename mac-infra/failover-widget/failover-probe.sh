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
ARCHIVE_DIR="${HARK_ARCHIVE_DIR:-$HOME/Documents/facility-archives}"
ARCHIVE_ALT="${HARK_ARCHIVE_ALT:-$HOME/Library/CloudStorage/GoogleDrive-max2k03@gmail.com/My Drive/facility-archives}"
ARCHIVE_GLOB="hub-backup-fluxuum-*.sql.gz"
# Written by facility-archive-backup.sh after each successful run. Lives under
# ~/Library/Logs, which macOS does not gate, so it stays readable when the
# archive folders themselves are not.
ARCHIVE_RECEIPT="${HARK_ARCHIVE_RECEIPT:-$HOME/Library/Logs/facility-archive-last.txt}"

SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"

# ---------- anderson-hub (primary) ----------
A_UP=down
A_LAST="--"
A_AGE=-1

if $SSH anderson-hub true 2>/dev/null; then
  A_UP=up
  # Returns two epochs — the newest reading and the Pi's own clock — as
  # "last|now" on psql's default separator. Ages are computed from the Pi's
  # clock, so a skewed Mac clock cannot invent staleness.
  #
  # Two rules keep this parsable by macOS's /bin/bash 3.2, which Übersicht uses:
  # the remote command is wrapped in SINGLE quotes so nothing needs escaping,
  # and the SQL contains no quotes of its own (hence epochs here and formatting
  # below, rather than to_char with a quoted format string). The earlier version
  # nested escaped quotes inside $( ), which 3.2 mis-scans — it runs past the
  # closing paren and dies on the next ")" it meets, at a baffling line number.
  ROW=$($SSH anderson-hub 'timeout 20 sudo -u postgres psql -tAX -d fluxuum -c "select coalesce(extract(epoch from max(created_at))::bigint,0), extract(epoch from now())::bigint from readings;"' 2>/dev/null)
  LAST_E="${ROW%%|*}"
  NOW_E="${ROW##*|}"
  case "$LAST_E" in ''|*[!0-9]*) LAST_E=0 ;; esac
  case "$NOW_E" in ''|*[!0-9]*) NOW_E=0 ;; esac
  if [ "$LAST_E" -gt 0 ] && [ "$NOW_E" -gt 0 ]; then
    A_AGE=$(( NOW_E - LAST_E ))
    [ "$A_AGE" -lt 0 ] && A_AGE=0
    A_LAST=$(date -r "$LAST_E" '+%m-%d %H:%M' 2>/dev/null || echo "--")
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
# Both archive folders sit in TCC-protected locations (~/Documents and
# ~/Library/CloudStorage). A scheduled or sandboxed job can stat them but gets
# handed an EMPTY listing of their contents — so "no files" here means "could
# not look", not "the backups are gone". Never report absence from that.
#
# Same ladder the staleness alarm uses: read the real folders when they are
# readable, otherwise fall back to the receipt the backup job leaves behind.
ARCH_N=-1
ARCH_AGE=-1
ARCH_SRC=unknown

# read_dir DIR — echo "count|newest_mtime", or return 1 if it cannot be read.
# A readable folder holding no archives returns "0|" — that is a real finding,
# distinct from a blocked listing, and must stay distinguishable from it.
read_dir() {
  local d="$1" entries n newest
  [ -d "$d" ] || return 1
  entries=$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')
  # Zero visible entries is the signature of a blocked listing, not an empty
  # folder — treat it as unreadable and let the receipt answer instead.
  [ "${entries:-0}" -gt 0 ] || return 1
  # shellcheck disable=SC2086
  n=$(ls -1 "$d"/$ARCHIVE_GLOB 2>/dev/null | wc -l | tr -d ' ')
  # shellcheck disable=SC2086
  newest=$(ls -1t "$d"/$ARCHIVE_GLOB 2>/dev/null | head -1)
  [ -n "$newest" ] || { echo "0|"; return 0; }
  echo "${n}|$(stat -f %m "$newest")"
}

# Prefer a folder that actually holds archives. A readable-but-empty folder is
# only reported once every location has been tried, so a blocked primary cannot
# mask a healthy Drive copy.
SAW_EMPTY=0
for dir in "$ARCHIVE_DIR" "$ARCHIVE_ALT"; do
  if HIT=$(read_dir "$dir"); then
    MTIME="${HIT##*|}"
    if [ -n "$MTIME" ]; then
      ARCH_N="${HIT%%|*}"
      ARCH_AGE=$(( ( $(date +%s) - MTIME ) / 3600 ))
      ARCH_SRC=disk
      break
    fi
    SAW_EMPTY=1
  fi
done

if [ "$ARCH_SRC" = unknown ] && [ "$SAW_EMPTY" = 1 ]; then
  ARCH_N=0
  ARCH_AGE=-1
  ARCH_SRC=disk
fi

if [ "$ARCH_SRC" = unknown ] && [ -r "$ARCHIVE_RECEIPT" ]; then
  R_EPOCH=$(sed -n 's/^epoch=//p' "$ARCHIVE_RECEIPT" | head -1 | tr -d '[:space:]')
  case "$R_EPOCH" in
    ''|*[!0-9]*) ;;
    *)
      ARCH_AGE=$(( ( $(date +%s) - R_EPOCH ) / 3600 ))
      ARCH_N=1
      ARCH_SRC=receipt
      ;;
  esac
fi

printf '{"anderson":{"up":"%s","last":"%s","age":%s},"backup":{"up":"%s"},"promoted":"%s","watcher":{"active":"%s","enabled":"%s"},"archive":{"count":%s,"age_h":%s,"source":"%s"},"checked":"%s"}\n' \
  "$A_UP" "$A_LAST" "${A_AGE:--1}" \
  "$B_UP" "$PROMOTED" "$W_ACTIVE" "$W_ENABLED" \
  "${ARCH_N:--1}" "${ARCH_AGE:--1}" "$ARCH_SRC" \
  "$(date '+%H:%M')"
