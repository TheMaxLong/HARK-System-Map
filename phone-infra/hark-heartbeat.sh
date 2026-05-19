#!/data/data/com.termux/files/usr/bin/bash
#
# HARK Phone Heartbeat
# Sends device telemetry to ntfy.sh every 5 minutes and on boot
# Expects: ntfy.sh account token in ~/.hark/ntfy-token
#

set -euo pipefail

TOPIC="hark-phones-b6d6f70e9913"
LOG_FILE="${HOME}/.hark/heartbeat.log"

# Ensure log dir exists
mkdir -p "$(dirname "$LOG_FILE")"

# Get device name (Android device name)
DEVICE_NAME=$(getprop ro.product.model 2>/dev/null || echo "unknown")

# Get battery percentage
BATTERY_PCT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "?")

# Get charging status
CHARGING_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "Unknown")
CHARGING="no"
[[ "$CHARGING_STATUS" =~ [Cc]harging ]] && CHARGING="yes"

# Get WiFi vs cellular (dumpsys connectivity output)
CONNECTIVITY=$(dumpsys connectivity 2>/dev/null | grep -i "active" | head -1 | xargs || echo "unknown")
NETWORK_TYPE="unknown"
if echo "$CONNECTIVITY" | grep -qi wifi; then
  NETWORK_TYPE="WiFi"
elif echo "$CONNECTIVITY" | grep -qi cellular; then
  NETWORK_TYPE="5G/LTE"
else
  NETWORK_TYPE="unknown"
fi

# Get Tailscale IP (expects tailscaled running)
TAILSCALE_IP="?"
if command -v tailscale &>/dev/null; then
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "?")
fi

# Build message
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
MESSAGE="Device: $DEVICE_NAME | Battery: ${BATTERY_PCT}% | Charging: $CHARGING | Network: $NETWORK_TYPE | Tailscale: $TAILSCALE_IP | $TIMESTAMP"

# Send to ntfy.sh
RESPONSE=$(curl -s -X POST \
  -H "Title: HARK Heartbeat: $DEVICE_NAME" \
  -d "$MESSAGE" \
  "https://ntfy.sh/$TOPIC" 2>&1)

# Log result
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sent: $MESSAGE | Response: $RESPONSE" >> "$LOG_FILE"

exit 0
