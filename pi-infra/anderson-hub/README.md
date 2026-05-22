# anderson-hub Pi Infrastructure

Scripts that run on the `anderson-hub` Pi (`100.123.152.77`) — the one with a
Tailscale subnet route into the facility LAN (`10.10.13.x`). This is the
natural host for any alert that needs to keep eyes on the production
controllers 24/7, because the Mac sees the facility only when on facility
wifi.

The Pi already runs Fluxuum API (:3001), Facility Tracker (:8080), and
Verdaccio. The phone (`phone-infra/sentinel/`) watches the Pi for health —
this directory is the inverse: scripts the Pi itself runs.

## Contents

| File | What it does |
|------|--------------|
| `run-flower-lights-out-check.sh` | Cron-invoked wrapper. Calls alexandria's `check-lights-out` script, throttles per-room signatures, fires ntfy on alert. |
| `install-flower-lights-out-check.sh` | Idempotent installer. Copies the wrapper into `~/.hark/bin/` and wires a `*/5 * * * *` crontab entry. |

## Flower lights-out alert — first-time setup on the Pi

Why this exists: 2026-05-22 AB1 lost power, ran at 65.5°F while AB3/AB4 sat at
80–83°F, Infinium HMI still showed Channel A/B "on", phone heartbeat didn't
catch it. The signal that *would* have caught it: room temp below threshold
during scheduled lights-on past the warmup grace. This pipeline reads that
signal off the existing HMI page every 5 minutes.

### Prerequisites on the Pi

```sh
# Node 24+ and pnpm (skip if already installed)
nvm install 24
nvm use 24
npm i -g pnpm@9

# Clone the alexandria repo into a known location
git clone git@github.com:themaxlong/alexandria.git ~/alexandria
cd ~/alexandria
pnpm install
```

### Fill in the tag maps

The 24 in-room TEMP probe tag IDs come from CannaMax's
`src/infinium-tagmap.ts`. Per the AB Infinium recon (2026-05-15), CORE
Overview A has the same pageId across AB / EF / GH, but the actual tag IDs
differ per controller. Edit on a workstation that has CannaMax checked out:

```
~/alexandria/data/tag-maps/AB/flower-temps.json    # AB1..AB8
~/alexandria/data/tag-maps/EF/flower-temps.json    # EF1..EF8
~/alexandria/data/tag-maps/GH/flower-temps.json    # GH1..GH8
```

Each room's `temp_tag` should be the Factotum integer tag ID for that room's
in-room TEMP NumEdit (the one CannaMax decodes as `temp_tag` for that zone).
Commit and pull on the Pi.

### Install

```sh
~/HARK-System-Map/pi-infra/anderson-hub/install-flower-lights-out-check.sh
```

That copies the wrapper to `~/.hark/bin/run-flower-lights-out-check.sh` and
adds a `*/5 * * * *` cron entry.

### Verify

```sh
# Manual run to confirm wiring (does NOT fire ntfy unless an alert triggers)
~/.hark/bin/run-flower-lights-out-check.sh
cat ~/.hark/flower-lights-out/last-output.json | jq '.alertCount, .roomsRead'
tail -20 ~/.hark/flower-lights-out/last-run.log

# Crontab present?
crontab -l | grep flower-lights-out
```

If `roomsRead` is 0 the tag maps are still `REPLACE_ME`. Fill them in.

## Operating notes

- **Cron cadence:** `*/5 * * * *`. Faster doesn't help (rooms cool over tens
  of minutes); slower risks missing short outages.
- **Throttling:** each unique alerting-room signature pages once per
  `THROTTLE_MIN` (default 30 min). Sustained outage = one alert, not 12.
- **Schedule:** see `data/tag-maps/lights-schedule.json` in alexandria.
  Day cycle 00:00–11:30, night cycle 12:00–23:30, threshold 72°F, warmup
  30 min.
- **Topic:** alerts post to ntfy.sh topic `hark-phones-b6d6f70e9913` —
  same topic the phone heartbeats use, so existing ntfy subscriptions on the
  Pixel 6 / Pixel 10 / Mac will receive them automatically.
- **Observation Doctrine:** the underlying alexandria script is read-only by
  type-level brand. The Pi wrapper only adds outbound ntfy posting. No write
  ever reaches the controller. See `alexandria/docs/SAFETY.md`.

## Disabling

```sh
crontab -l | grep -v flower-lights-out | crontab -
```

That removes the cron line. Wrapper script and state dir stick around for
re-enable.
