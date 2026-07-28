#!/usr/bin/env bash
#
# Launch the app in the Simulator already signed in, pointed at a local backend.
#
# Signing in by hand means typing an address and opening a mail client; this
# does the same thing the tests do — open a login session, click the emailed
# link on the app's behalf — and hands the session id to the app, which claims
# it on launch (DEBUG only, see AuthStore.restore).
#
# Usage:
#   BACKEND_LOG=/tmp/backend.log Scripts/run-dev-session.sh
#
set -euo pipefail

API="${AVANGARD_API_BASE:-http://localhost:3000}"
EMAIL="${TEST_EMAIL:-ios-test@avangard.local}"
BACKEND_LOG="${BACKEND_LOG:-}"

if [[ -z "$BACKEND_LOG" || ! -f "$BACKEND_LOG" ]]; then
  echo "error: set BACKEND_LOG to the file the backend's stdout is being written to." >&2
  exit 1
fi

if ! curl -sf "$API/api/health" >/dev/null; then
  echo "error: no backend answering at $API — start it with 'pnpm dev'." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

DEVICE_ID="${SIMULATOR_ID:-$(xcrun simctl list devices available --json \
  | python3 -c 'import json,sys; ds=json.load(sys.stdin)["devices"]; \
    print(next(d["udid"] for k in sorted(ds, reverse=True) for d in ds[k] if "iPhone" in d["name"]))')}"

before="$(wc -l < "$BACKEND_LOG")"
SID="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"

curl -sf -X POST "$API/auth/request-link" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"loginSessionId\":\"$SID\"}" -o /dev/null

for _ in $(seq 1 40); do
  TOKEN="$(tail -n "+$((before + 1))" "$BACKEND_LOG" \
    | grep -o 'token=[A-Za-z0-9_-]*' | tail -1 | cut -d= -f2)"
  [[ -n "$TOKEN" ]] && break
  sleep 0.25
done
[[ -n "${TOKEN:-}" ]] || { echo "error: no magic-link token appeared in $BACKEND_LOG" >&2; exit 1; }

curl -sf "$API/auth/verify?token=$TOKEN" -o /dev/null
echo "==> login session verified for $EMAIL"

DERIVED="${DERIVED_DATA:-$(mktemp -d)}"
xcodegen generate >/dev/null
xcodebuild build \
  -project AvangardVPN.xcodeproj \
  -scheme AvangardVPN \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" >/dev/null

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl terminate "$DEVICE_ID" com.avangard.vpn 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$DERIVED/Build/Products/Debug-iphonesimulator/AvangardVPN.app"

SIMCTL_CHILD_AVANGARD_API_BASE="$API" \
SIMCTL_CHILD_AVANGARD_DEV_SESSION_ID="$SID" \
  xcrun simctl launch "$DEVICE_ID" com.avangard.vpn >/dev/null

echo "==> launched signed in, talking to $API"
