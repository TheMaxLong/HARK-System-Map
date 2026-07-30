# Failover Widget (Übersicht, Mac)

Desktop widget showing whether the failover can actually fire, plus whether
anderson-hub is still collecting. Read-only — it tests for one file and runs one
`SELECT`. It cannot promote, demote, or delete anything.

## Install

The umlaut in `Übersicht` is stored decomposed on macOS, so a pasted `Ü` often
won't match. The `*bersicht` glob avoids the problem:

```sh
W=$(ls -d ~/Library/Application\ Support/*bersicht/widgets | head -1)
mkdir -p "$W/failover" && cd "$W/failover"
BASE=https://raw.githubusercontent.com/TheMaxLong/HARK-System-Map/134f694c452517e9e5ca43e0980f56bacae6a12a/mac-infra/failover-widget
curl -fsSLO "$BASE/failover.jsx"
curl -fsSLO "$BASE/failover-probe.sh"
chmod +x failover-probe.sh
```

Übersicht reloads on save. To test the probe on its own — it prints one JSON line:

```sh
bash "$W/failover/failover-probe.sh"
```

## What it shows

The banner is driven by `/home/pi/PROMOTED_AT`, because that single file is what
decides whether failover can fire at all:

| Banner | Meaning |
|---|---|
| `FAILOVER DISARMED` | Marker present. Auto-promotion cannot happen. |
| `FAILOVER ARMED` | Marker cleared. Watcher can promote. |
| `STATE UNKNOWN` | hub-backup unreachable — never shown as green. |

Below that: anderson-hub with its **last reading age**, hub-backup reachability,
and off-site archive count + age. The anderson-hub dot turns amber when readings
are over 30 minutes stale *even though the host is up* — the readings-staleness
guard that exists on neither Pi, and the exact condition that went unnoticed for
an hour on 2026-07-29.

## Two things to know

**Archive path.** Defaults to `~/Documents/facility-archive`. Point it elsewhere
with `export HARK_ARCHIVE_DIR=/real/path`. Until it's right, that row reads
"folder missing".

**Do not lower the refresh interval.** `refreshFrequency` is 15 min, which is
~96 `max(created_at)` scans a day against an unindexed 64MB `readings` table.
The 2s-polling flux-widget is what drove anderson-hub to 79°C in July (~66
req/min, six seq-scans each). Add the `created_at` index the system map lists as
still-open before going faster.
