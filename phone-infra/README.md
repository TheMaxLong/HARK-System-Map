# HARK Phone Infrastructure

Device telemetry heartbeats sent to ntfy.sh every 5 minutes + on boot.

## Topic

**`hark-phones-b6d6f70e9913`** — the ntfy.sh public topic for all HARK device heartbeats.

This topic is not secret (it's random enough), but treat it like one. Share only with people you want monitoring your devices.

## Files

- **`hark-heartbeat.sh`** — Main script. Collects battery, network, Tailscale IP, charging status. Sends to ntfy.sh.
- **`install-on-pixel6.sh`** — Deployment script. Copies heartbeat, installs cronie, sets up crontab + Termux:Boot.
- **`query-heartbeats.sh`** — Query latest heartbeats from Mac terminal.

## Deployment

### Pixel 6 (first time)

```bash
cd phone-infra
./install-on-pixel6.sh
```

This will:
1. Copy `hark-heartbeat.sh` to Pixel 6 home
2. Install `cronie` (cron daemon for Termux)
3. Set up crontab with `*/5 * * * *` (every 5 min) + `@reboot`
4. Install Termux:Boot startup script

Verify:
```bash
ssh pixel6 'crontab -l'
ssh pixel6 'tail -20 ~/.hark/heartbeat.log'
```

### Pixel 10 (when connected)

One-liner (no script needed, scp + ssh):
```bash
scp phone-infra/hark-heartbeat.sh pixel10:~/hark-heartbeat.sh && \
ssh pixel10 'chmod +x ~/hark-heartbeat.sh && mkdir -p ~/.hark && \
pkg install -y cronie && crond && \
(echo "*/5 * * * * ~/hark-heartbeat.sh"; echo "@reboot ~/hark-heartbeat.sh") | crontab - && \
mkdir -p ~/.termux/boot && \
cat > ~/.termux/boot/hark-init.sh << "BOOT"
#!/data/data/com.termux/files/usr/bin/bash
crond 2>/dev/null || pgrep crond >/dev/null || true
sleep 2
~/hark-heartbeat.sh
BOOT
chmod +x ~/.termux/boot/hark-init.sh'
```

## Query from Mac

Get latest 5 heartbeats:
```bash
cd phone-infra && ./query-heartbeats.sh
```

Or directly:
```bash
curl -s "https://ntfy.sh/hark-phones-b6d6f70e9913/json?limit=5" | jq -r '.[] | "\(.time | strftime("%Y-%m-%d %H:%M:%S")) | \(.title) | \(.message)"' | sort -r
```

Or subscribe on the web:
```
https://ntfy.sh/hark-phones-b6d6f70e9913
```

## What Gets Sent

Each heartbeat includes:
- Device model (e.g., "Pixel 6")
- Battery percentage
- Charging status (yes/no)
- Network type (WiFi/5G/LTE/unknown)
- Tailscale IP (if available)
- UTC timestamp

Example message:
```
Device: Pixel 6 | Battery: 87% | Charging: no | Network: WiFi | Tailscale: 100.72.211.71 | 2026-05-19T16:16:16Z
```

## Logs

Each device keeps its own log at `~/.hark/heartbeat.log`:
```bash
ssh pixel6 'tail -50 ~/.hark/heartbeat.log'
```

## Troubleshooting

**Cron not firing?**
```bash
ssh pixel6 'pgrep crond'  # should return a PID
ssh pixel6 'crond'        # restart if needed
```

**Heartbeat doesn't fire at boot?**
Check that Termux:Boot is enabled in settings and the script is executable:
```bash
ssh pixel6 'ls -la ~/.termux/boot/hark-init.sh'
```

**Battery/network showing as `?`?**
Some Android 13+ devices restrict `/sys/class/power_supply` access. This is normal. Tailscale IP will still work if tailscaled is running.

## Architecture Decision

Used ntfy.sh (public, topic-based) instead of a private webhook:
- Zero infrastructure — no server to run
- Works across locations (Tailscale, cell, WiFi)
- Can subscribe from any device
- Payload is small (one-liner)
- No auth needed (topic is the secret)

If you ever need to rotate the topic, regenerate it here and update both scripts.
