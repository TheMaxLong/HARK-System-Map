#!/bin/bash
#
# Deploy HARK Phone Heartbeat to Pixel 6 via Termux
# No arguments needed — uses hardcoded ntfy topic (hark-phones-b6d6f70e9913)
#

set -euo pipefail

REMOTE_HOST="pixel6"
REMOTE_HOME="/data/data/com.termux/files/home"

echo "=== Deploying HARK Heartbeat to $REMOTE_HOST ==="
echo ""

# Step 1: Copy scripts to phone
echo "1. Copying heartbeat script..."
scp ./hark-heartbeat.sh "$REMOTE_HOST:$REMOTE_HOME/hark-heartbeat.sh"
ssh "$REMOTE_HOST" "chmod +x $REMOTE_HOME/hark-heartbeat.sh"

# Step 2: Create .hark directory
echo "2. Creating .hark directory..."
ssh "$REMOTE_HOST" "mkdir -p $REMOTE_HOME/.hark"

# Step 3: Install cronie if not present
echo "3. Checking cronie..."
ssh "$REMOTE_HOST" "pkg list-installed | grep -q cronie || pkg install -y cronie" || true

# Step 4: Start crond service
echo "4. Starting cron daemon..."
ssh "$REMOTE_HOST" "crond || pgrep crond >/dev/null || true"

# Step 5: Set up crontab (every 5 minutes + @reboot)
echo "5. Installing crontab..."
ssh "$REMOTE_HOST" << 'EOF'
cat > "$HOME/.crontab-tmp" << 'CRON'
*/5 * * * * /data/data/com.termux/files/home/hark-heartbeat.sh
@reboot /data/data/com.termux/files/home/hark-heartbeat.sh
CRON
crontab "$HOME/.crontab-tmp"
rm "$HOME/.crontab-tmp"
EOF

# Step 6: Install Termux:Boot script
echo "6. Installing Termux:Boot startup script..."
ssh "$REMOTE_HOST" << 'EOF'
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/hark-init.sh" << 'BOOT'
#!/data/data/com.termux/files/usr/bin/bash
# HARK Termux:Boot initialization
# Ensures crond starts and fires heartbeat on boot

crond 2>/dev/null || pgrep crond >/dev/null || true
sleep 2
/data/data/com.termux/files/home/hark-heartbeat.sh
BOOT
chmod +x "$HOME/.termux/boot/hark-init.sh"
EOF

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Verification:"
echo "  - Check crontab: ssh $REMOTE_HOST 'crontab -l'"
echo "  - Check logs: ssh $REMOTE_HOST 'tail -20 ~/.hark/heartbeat.log'"
echo ""
