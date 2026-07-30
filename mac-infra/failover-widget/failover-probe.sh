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
ARCHIVE_DIR="${HARK_ARCHIVE_DIR:-$HOME/Documents/facility-archive}"
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

printf '{"anderson":{"up":"%s","last":"%s","age":%s},"backup":{"up":"%s"},"promoted":"%s","watcher":{"active":"%s","enabled":"%s"},"archive":{"count":%s,"age_h":%s},"checked":"%s"}\n' \
  "$A_UP" "$A_LAST" "${A_AGE:--1}" \
  "$B_UP" "$PROMOTED" "$W_ACTIVE" "$W_ENABLED" \
  "${ARCH_N:--1}" "${ARCH_AGE:--1}" \
  "$(date '+%H:%M')"
