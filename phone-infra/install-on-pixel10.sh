#!/data/data/com.termux/files/usr/bin/bash
# HARK Pixel 10 Setup — run this once in Termux on Pixel 10
# Sets up: SSH server, heartbeat cron, Termux:Boot auto-start

set -e

echo "[1/6] Installing packages..."
pkg install -y openssh cronie

echo "[2/6] Setting up SSH authorized_keys..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys << 'PUBKEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOfNQO5CQm2ZFhKGy6uu/xMCti//uZxLKGsc4mvPVR2R max@mac-20260516
PUBKEY
chmod 600 ~/.ssh/authorized_keys

echo "[3/6] Starting SSH daemon..."
pkill sshd 2>/dev/null || true
sshd

echo "[4/6] Installing heartbeat script..."
mkdir -p ~/.hark
cat > ~/hark-heartbeat.sh << 'HEARTBEAT'
#!/data/data/com.termux/files/usr/bin/bash
TOPIC="hark-phones-b6d6f70e9913"
LOG_FILE="${HOME}/.hark/heartbeat.log"
mkdir -p "$(dirname "$LOG_FILE")"
DEVICE_NAME=$(getprop ro.product.model 2>/dev/null || echo "Pixel 10")
BATTERY_PCT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "?")
CHARGING_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "Unknown")
CHARGING="no"
[[ "$CHARGING_STATUS" =~ [Cc]harging ]] && CHARGING="yes"
TAILSCALE_IP="?"
if command -v tailscale &>/dev/null; then
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "?")
fi
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
MESSAGE="Device: $DEVICE_NAME | Battery: ${BATTERY_PCT}% | Charging: $CHARGING | Tailscale: $TAILSCALE_IP | $TIMESTAMP"
curl -s -X POST -H "Title: HARK Heartbeat: $DEVICE_NAME" -d "$MESSAGE" "https://ntfy.sh/$TOPIC" > /dev/null
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sent: $MESSAGE" >> "$LOG_FILE"
HEARTBEAT
chmod +x ~/hark-heartbeat.sh

echo "[5/6] Setting up cron (every 5 min + on reboot)..."
crond 2>/dev/null || true
(crontab -l 2>/dev/null | grep -v hark-heartbeat; echo "*/5 * * * * ~/hark-heartbeat.sh"; echo "@reboot ~/hark-heartbeat.sh") | crontab -

echo "[6/6] Setting up Termux:Boot auto-start..."
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/hark-init.sh << 'BOOT'
#!/data/data/com.termux/files/usr/bin/bash
sleep 5
sshd 2>/dev/null || true
sleep 2
crond 2>/dev/null || pgrep crond > /dev/null || true
sleep 2
~/hark-heartbeat.sh
BOOT
chmod +x ~/.termux/boot/hark-init.sh

echo ""
echo "=== DONE ==="
echo "SSH running on port 8022"
echo "Heartbeat fires every 5 min to hark-phones-b6d6f70e9913"
echo "From Mac: ssh -p 8022 $(whoami)@100.75.250.48"
echo ""
echo "Firing test heartbeat now..."
~/hark-heartbeat.sh && echo "Heartbeat sent to ntfy.sh"
