#!/usr/bin/env bash
# run-flower-lights-out-check.sh — Cron wrapper for the alexandria
# check-lights-out script. Runs on anderson-hub Pi which has a Tailscale
# subnet route into 10.10.13.x at the facility.
#
# READ-ONLY: the underlying script only GETs the same data the HMI's own
# page polls. No setpoint writes, no commands. Per docs/SAFETY.md in
# alexandria.
#
# Throttles ntfy alerts to once per 30 min per room signature, so a sustained
# outage doesn't re-page every 5 minutes.

set -uo pipefail

ALEXANDRIA_DIR="${ALEXANDRIA_DIR:-$HOME/alexandria}"
STATE_DIR="${STATE_DIR:-$HOME/.hark/flower-lights-out}"
LOG_FILE="${LOG_FILE:-$STATE_DIR/last-run.log}"
LAST_OUTPUT="${LAST_OUTPUT:-$STATE_DIR/last-output.json}"
NTFY_TOPIC="${NTFY_TOPIC:-hark-phones-b6d6f70e9913}"
THROTTLE_MIN="${THROTTLE_MIN:-30}"

mkdir -p "$STATE_DIR"

if [[ ! -d "$ALEXANDRIA_DIR" ]]; then
  echo "[$(date -u +%FT%TZ)] alexandria repo missing at $ALEXANDRIA_DIR" >> "$LOG_FILE"
  exit 1
fi

cd "$ALEXANDRIA_DIR" || exit 1

# Run the engine in dry-run mode (we handle ntfy here so we can throttle).
RAW_OUTPUT="$(pnpm --silent --filter @alexandria/adapter-http-websocket run check-lights-out -- --dry-run 2>>"$LOG_FILE")"
EXIT_CODE=$?

# The script's JSON summary is the only thing on stdout. Persist it for later
# diffs and so other tooling can read state.
echo "$RAW_OUTPUT" > "$LAST_OUTPUT"

# Parse JSON, find alerting rooms, decide whether to fire ntfy.
ALERTS_JSON="$(LAST_OUTPUT="$LAST_OUTPUT" python3 - <<'PY'
import json, sys, os, pathlib
try:
    data = json.loads(pathlib.Path(os.environ["LAST_OUTPUT"]).read_text())
except Exception as e:
    print(f"PARSE_ERROR: {e}", file=sys.stderr)
    sys.exit(0)
alerts = [r for r in data.get("rooms", []) if r.get("alert")]
if not alerts:
    sys.exit(0)
print(json.dumps({
    "title": "Flower lights-out: " + ", ".join(r["room"] for r in alerts),
    "body": "\n".join(
        f'{r["room"]}: {r["tempF"]:.1f}°F (lights-on +{r["minutesIntoCycle"]}m, threshold {data["thresholdF"]}°F)'
        for r in alerts
    ),
    "signature": ",".join(sorted(r["room"] for r in alerts)),
}))
PY
)"

if [[ -z "$ALERTS_JSON" ]]; then
  echo "[$(date -u +%FT%TZ)] OK — no alerts (exit=$EXIT_CODE)" >> "$LOG_FILE"
  exit 0
fi

TITLE="$(echo "$ALERTS_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["title"])')"
BODY="$(echo "$ALERTS_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["body"])')"
SIGNATURE="$(echo "$ALERTS_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["signature"])')"

# Throttle: if same room signature fired within THROTTLE_MIN, log and skip.
THROTTLE_FILE="$STATE_DIR/throttle.$(echo -n "$SIGNATURE" | tr ',' '_' | tr -cd 'A-Za-z0-9_').stamp"
NOW=$(date +%s)
if [[ -f "$THROTTLE_FILE" ]]; then
  LAST=$(cat "$THROTTLE_FILE")
  AGE=$((NOW - LAST))
  if (( AGE < THROTTLE_MIN * 60 )); then
    echo "[$(date -u +%FT%TZ)] ALERT $SIGNATURE throttled (age=${AGE}s)" >> "$LOG_FILE"
    exit 0
  fi
fi
echo "$NOW" > "$THROTTLE_FILE"

# Fire ntfy at priority 5 (max). Best-effort — if the post fails, log it.
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  -H "Title: $TITLE" \
  -H "Priority: 5" \
  -H "Tags: rotating_light,thermometer" \
  -d "$BODY" \
  "https://ntfy.sh/$NTFY_TOPIC")
echo "[$(date -u +%FT%TZ)] FIRED $SIGNATURE ntfy_http=$HTTP_CODE" >> "$LOG_FILE"
echo "$BODY" >> "$LOG_FILE"
