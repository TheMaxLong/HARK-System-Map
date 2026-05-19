#!/bin/bash
#
# Query HARK Phone Heartbeats from ntfy.sh
# Run from Mac terminal to see latest device telemetry
#
# Usage: ./query-heartbeats.sh [limit]
# Example: ./query-heartbeats.sh 10
#

LIMIT="${1:-5}"
TOPIC="hark-phones"

echo "=== HARK Phone Heartbeats (last $LIMIT) ==="
echo ""

curl -s "https://ntfy.sh/$TOPIC/json?limit=$LIMIT" | jq -r '.[] | "\(.time | strftime("%Y-%m-%d %H:%M:%S")) | \(.title) | \(.message)"' | sort -r

echo ""
