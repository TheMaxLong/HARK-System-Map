#!/bin/bash
# bridge-runner.sh — wrapper that sources env, then exec's bridge.sh
# Usage: bridge-runner.sh <phone_host>
set -e
[ -f "$HOME/.hark/env" ] && source "$HOME/.hark/env"
exec /Users/max/Documents/GitHub/HARK-System-Map/phone-infra/voice/bridge.sh "$1"
