#!/data/data/com.termux/files/usr/bin/bash
# watch-pi-health.sh — Checks BOTH Pis and their key services, independently.
#
# anderson-hub is the production primary; hub-backup is the standby at the condo.
# Each host is probed and alerted on separately, and every alert names the host it
# came from. A healthy standby must never mask a dead primary.
#
# It did exactly that from 2026-05-27 to 2026-07-30: commit 82dabaf repointed the
# HTTP probe to hub-backup during the SD-card death and it was never repointed back
# after anderson-hub resumed primary on 05-28. The ssh probes kept hitting
# anderson-hub via the `pi` alias, so one composite state mixed two machines — and
# the "$ROOT = up" guard suppressed anderson-hub service alerts based on
# hub-backup's reachability.
source ~/sentinel/lib/common.sh

WATCHER=pi-health
STATE_FILE="$STATE_DIR/$WATCHER.json"

ANDERSON_HOST="anderson-hub.tailf0f27a.ts.net"
ANDERSON_SSH="pi"                # long-standing ssh alias for anderson-hub
BACKUP_HOST="hub-backup.tailf0f27a.ts.net"
BACKUP_SSH="hub-backup"          # ssh legs self-park if this alias isn't configured

# Helper: any HTTP response code 1xx-5xx means the server is alive.
# Only "000" or empty means it failed to reach the service.
is_alive() { [ -n "$1" ] && [ "$1" != "000" ]; }

# http_up HOST — Tailscale reachability of the host root.
http_up() {
  local CODE
  CODE=$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "https://$1/")
  [ "$CODE" = "200" ] && echo up || echo down
}

# svc_state SSH_ALIAS PORT — is a service answering on the host's localhost?
svc_state() {
  local CODE
  CODE=$(ssh -o ConnectTimeout=4 -o BatchMode=yes "$1" \
    "curl -s -o /dev/null --max-time 3 -w '%{http_code}' http://localhost:$2/" 2>/dev/null)
  is_alive "$CODE" && echo up || echo down
}

# ssh_ready ALIAS — true if the alias resolves and accepts a batch-mode login.
ssh_ready() { ssh -o ConnectTimeout=4 -o BatchMode=yes "$1" true 2>/dev/null; }

# ---------- anderson-hub (PRIMARY) ----------
A_ROOT=$(http_up "$ANDERSON_HOST")
A_FLUX=unknown
A_FT=unknown

if [ "$A_ROOT" = "down" ]; then
  alert_throttled "anderson-root-down" "critical" "anderson-hub unreachable" \
    "PRIMARY anderson-hub is not responding via Tailscale."
else
  A_FLUX=$(svc_state "$ANDERSON_SSH" 3001)
  A_FT=$(svc_state "$ANDERSON_SSH" 8080)

  if [ "$A_FLUX" = "down" ]; then
    alert_throttled "anderson-flux-down" "warn" "Fluxuum API down (anderson-hub)" \
      "anderson-hub is reachable but :3001 is not responding."
  fi
  if [ "$A_FT" = "down" ]; then
    alert_throttled "anderson-ft-down" "warn" "Facility Tracker down (anderson-hub)" \
      "anderson-hub is reachable but :8080 is not responding."
  fi
fi

# ---------- hub-backup (STANDBY / failover target) ----------
# Unreachable is critical: if the standby is dead there is nothing to fail over to.
# Its individual services are digest-only — as a cold standby they are deliberately
# stopped, so pushing on them would be noise. Reachability is the signal that matters.
B_ROOT=$(http_up "$BACKUP_HOST")
B_FLUX=unknown
B_FT=unknown

if [ "$B_ROOT" = "down" ]; then
  alert_throttled "backup-root-down" "critical" "hub-backup unreachable" \
    "STANDBY hub-backup is not responding via Tailscale — no failover target."
elif ssh_ready "$BACKUP_SSH"; then
  B_FLUX=$(svc_state "$BACKUP_SSH" 3001)
  B_FT=$(svc_state "$BACKUP_SSH" 8080)
  [ "$B_FLUX" = "down" ] && log_digest warn "$WATCHER" "hub-backup :3001 down"
  [ "$B_FT" = "down" ] && log_digest warn "$WATCHER" "hub-backup :8080 down"
fi

# ---------- compose + recovery ----------
CURR="anderson[root=$A_ROOT flux=$A_FLUX ft=$A_FT] backup[root=$B_ROOT flux=$B_FLUX ft=$B_FT]"
PREV=$(cat "$STATE_FILE" 2>/dev/null || echo "")

if [ "$CURR" != "$PREV" ] && [ -n "$PREV" ]; then
  log_digest info "$WATCHER" "state change: $PREV -> $CURR"
fi

echo "$CURR" > "$STATE_FILE"
