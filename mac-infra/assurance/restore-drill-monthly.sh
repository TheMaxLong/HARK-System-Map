#!/bin/bash
# restore-drill-monthly.sh — the once-a-month "does it actually come back" run.
#
# gzip -t proves an archive is not truncated. It proves NOTHING about whether it
# restores. An untested backup is not a backup, it is a hope — so once a month
# one real archive is restored into a disposable database and a real row is read
# back out.
#
# This exists as a separate job so the DAILY prover never depends on Docker being
# open. If it did, every morning Docker happened to be closed would produce a
# "could not check" alert: true, useless, and constant. That is how the 09:00
# archive alarm turned into something to scroll past, and an alert nobody acts on
# is a defect, not a nuisance.
#
# It starts Docker itself rather than asking Max to remember. If Docker cannot be
# started, the drill reports `blocked` with the unblocker — never a false pass and
# never a false alarm about the backups.
#
# Created 2026-07-30.

set -o pipefail

LOG_FILE="$HOME/Library/Logs/facility-assurance.log"
log() { echo "[$(TZ=America/Los_Angeles date -Iseconds)] restore-drill: $*" | tee -a "$LOG_FILE"; }

log "monthly restore drill starting"

if ! command -v docker >/dev/null 2>&1; then
  log "docker not installed — handing off to the prover, which will record it as blocked"
else
  if ! docker info >/dev/null 2>&1; then
    log "docker daemon not running — starting Docker Desktop"
    open -a Docker 2>/dev/null || log "could not launch Docker Desktop"
    # Docker Desktop takes a while from cold. Wait, but not forever: a drill that
    # hangs is worse than one that reports it could not run.
    for i in $(seq 1 60); do
      docker info >/dev/null 2>&1 && { log "docker ready after ~$((i*5))s"; break; }
      sleep 5
    done
    docker info >/dev/null 2>&1 || log "docker never came up — the drill will record blocked"
  else
    log "docker already running"
  fi
fi

RUN_MONTHLY=1 bash "$HOME/bin/prove-archives.sh"
rc=$?

log "monthly restore drill finished (prover rc=$rc)"
exit $rc
