# backup-hub Pi Infrastructure

Scripts that run on the **backup-hub** Pi — the second always-on Pi at the
facility.

## What backup-hub is (confirmed 2026-05-24)

- **Always on**, runs 24/7.
- **Has the Tailscale subnet route into `10.10.13.x`** — same facility-LAN reach
  as anderson-hub, so it *can* reach the Infinium controllers directly.
- **Current role: cross-watchdog only.** It does not poll the controllers today.
  It watches that anderson-hub's flower lights-out checker is still alive.

Because it already has controller reach, promoting it to **hot standby** later
(both Pis poll on offset schedules, dedup via the shared ntfy topic) is a
config change, not a rebuild. Not doing that yet — watchdog first.

## Why a cross-watchdog exists

The AB1 outage (2026-05-22) slipped because nothing watched the rooms. The
flower lights-out checker on anderson-hub fixed that. But it introduced a new,
quieter blind spot: **if the checker itself stops** (cron dies, Node crash, a
bad `git pull`, a tag-map parse error) while the Pi stays up and pingable,
nothing notices the rooms went unwatched.

`anderson-hub`'s own health is watched by the phone-side
`phone-infra/sentinel/watch-pi-health.sh`, but that only catches the Pi going
*down* — not the checker silently failing while the Pi is fine.

backup-hub closes that gap: don't just watch the device, watch that the watcher
is working.

## How it works

```
anderson-hub                                   backup-hub
────────────                                   ──────────
run-flower-lights-out-check.sh (every 5 min)
  └─ posts min-priority heartbeat
     "HARK Flower Check"  ──────►  ntfy hark-phones-b6d6f70e9913
                                              │
                                   watch-flower-check.sh (every 5 min)
                                     └─ polls topic for latest "HARK Flower
                                        Check" heartbeat
                                        ├─ fresh (< 12 min): log OK, silent
                                        └─ stale / missing: PAGE priority 5
                                           "Room-watcher SILENT / STALE"
```

The heartbeat is min-priority (priority 1) so it doesn't buzz phones — it's just
a tick in the message stream for the watchdog to read. Only the watchdog's
"checker is down" page is high-priority.

## Setup

No alexandria clone, no controller access required for the watchdog.

```sh
# Pull the HARK-System-Map repo onto backup-hub (if not already there)
git clone git@github.com:themaxlong/HARK-System-Map.git ~/HARK-System-Map

# Install the watchdog cron
~/HARK-System-Map/pi-infra/backup-hub/install-flower-check-watchdog.sh
```

That copies `watch-flower-check.sh` to `~/.hark/bin/` and adds a `*/5 * * * *`
cron entry.

### Prerequisite on anderson-hub

The heartbeat only flows if anderson-hub is running the updated
`run-flower-lights-out-check.sh` (the one that posts "HARK Flower Check"). If
you installed the anderson-hub job before 2026-05-24, re-run its installer to
pick up the heartbeat emission.

## Verify

```sh
# Manual run (won't page unless the heartbeat is actually stale)
~/.hark/bin/watch-flower-check.sh
tail -10 ~/.hark/flower-check-watchdog/watchdog.log

# Should log "OK — last heartbeat Ns ago" once anderson-hub has run at least once.
crontab -l | grep flower-check
```

To test the alarm path: stop anderson-hub's cron for ~15 min and confirm
backup-hub pages "Room-watcher STALE".

## Tuning

- `STALE_SEC` (default 720 = 12 min): how long without a heartbeat before
  paging. 12 min = 2 missed 5-min cycles + buffer (matches the Pixel 10
  watchdog convention).
- `THROTTLE_MIN` (default 30): a sustained outage of the checker pages once per
  30 min, not every 5.
- `NTFY_TOPIC` / `HEARTBEAT_TITLE`: must match what anderson-hub posts. Defaults
  align out of the box.

## Disabling

```sh
crontab -l | grep -v flower-check | crontab -
```
