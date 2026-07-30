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
BASE=https://raw.githubusercontent.com/TheMaxLong/HARK-System-Map/15962c85dce9b189cfecb030e97b74abcce4fb31/mac-infra/failover-widget
curl -fsSLO "$BASE/failover.jsx"
curl -fsSLO "$BASE/failover-probe.sh"
chmod +x failover-probe.sh
```

Übersicht reloads on save. To test the probe on its own — it prints one JSON line:

```sh
bash "$W/failover/failover-probe.sh"
```

## Position and display

**Move it:** drag by the title bar. The position is saved and survives refreshes
and restarts. To send it back to the top-right corner, open the widget's web
inspector and run `localStorage.removeItem("failover-widget-pos")`, or edit
`HOME_TOP` / `HOME_RIGHT` at the top of `failover.jsx`.

If dragging does nothing, the desktop layer is in click-through mode — enable
interaction for the widget from the Übersicht menu bar icon, then try again.

**Pin it to one display:** this is a per-widget setting in Übersicht's own UI,
not something the widget file controls. Open the Übersicht menu bar icon, find
this widget in the list, and set which screen it appears on. There is no
`screens` export to set in code.

## What it shows

The banner answers one question — *can the failover actually promote right now?*
That takes both the marker file and the unit state, because a masked or stopped
watcher cannot fire regardless of what `/home/pi/PROMOTED_AT` says:

| Banner | Meaning |
|---|---|
| `FAILOVER ARMED` | Watcher running, marker clear. It can promote. |
| `FAILOVER OFF` | Watcher masked or not running. It cannot promote. |
| `FAILOVER BLOCKED` | Watcher running, but the marker stops it. |
| `STATE UNKNOWN` | hub-backup unreachable — never shown as green. |

Green means *armed*, which is only good once both Pis hold the same readings.
While they differ, armed is the dangerous state — see the recovery checklist.

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
