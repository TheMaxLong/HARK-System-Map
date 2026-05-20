#!/data/data/com.termux/files/usr/bin/bash
# sshd-watchdog — runs every minute via cron; ensures sshd is alive.
# If Android killed it, this respawns it within 60 seconds.
pgrep -x sshd >/dev/null || sshd
