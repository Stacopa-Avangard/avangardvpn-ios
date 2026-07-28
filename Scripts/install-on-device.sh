#!/usr/bin/env bash
#
# Build and install the device-test app onto a connected iPhone.
#
# Free-signed builds expire after 7 days, so this gets run again every time the
# app stops opening. Doing it from the CLI avoids clicking through Xcode each
# time.
#
# Usage:
#   DEVELOPMENT_TEAM=XXXXXXXXXX Scripts/install-on-device.sh
#
# DEVELOPMENT_TEAM is your **Personal Team** id, not an organisation's — it is
# deliberately not committed here. Find it with:
#
#   security find-identity -v -p codesigning
#   security find-certificate -c "<the Apple Development line>" -p \
#     | openssl x509 -noout -subject      # the OU=... field is the team id
#
# Prerequisites on the phone, both one-time:
#   - Settings → Privacy & Security → Developer Mode → on (reboots the phone)
#   - After first install: Settings → General → VPN & Device Management →
#     trust the developer certificate
#
set -euo pipefail

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "error: set DEVELOPMENT_TEAM to your Personal Team id." >&2
  echo "       security find-identity -v -p codesigning   # then read OU= from the cert" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

DERIVED="${DERIVED_DATA:-$(mktemp -d)}"

# Pick the connected device unless one was named explicitly.
#
# Parsed from JSON, not the table: both the device name and the model contain
# spaces ("Acer Swift's iPhone", "iPhone 12 (iPhone13,2)"), so splitting the
# table on whitespace picks the wrong column.
DEVICE_ID="${DEVICE_ID:-$(
  xcrun devicectl list devices --json-output /tmp/avangard-devices.json >/dev/null 2>&1
  python3 - <<'PY' 2>/dev/null
import json
try:
    devices = json.load(open('/tmp/avangard-devices.json'))['result']['devices']
except Exception:
    raise SystemExit
for d in devices:
    if d.get('connectionProperties', {}).get('tunnelState') == 'connected':
        print(d['identifier'])
        break
PY
)}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "error: no connected device found." >&2
  echo "       Plug the iPhone in, unlock it, and trust this Mac." >&2
  echo "       If it shows as 'available' rather than 'connected', Developer Mode is off." >&2
  exit 1
fi

echo "==> device $DEVICE_ID, team $DEVELOPMENT_TEAM"
xcodegen generate >/dev/null

echo "==> building"
xcodebuild build \
  -project AvangardVPN.xcodeproj \
  -scheme AvangardVPNDeviceTest \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  | grep -E "error:|warning: .*\.swift|BUILD" || true

APP="$DERIVED/Build/Products/Debug-iphoneos/AvangardVPNDeviceTest.app"
[[ -d "$APP" ]] || { echo "error: build produced no app bundle" >&2; exit 1; }

# Sanity check: this variant must carry no paid capability, or a free team
# cannot sign it and the failure is confusing.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "application-groups\|networkextension"; then
  echo "error: the built app carries a paid entitlement — a free team cannot sign this." >&2
  exit 1
fi

echo "==> installing"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tail -3

echo "==> done. Signed by team $DEVELOPMENT_TEAM; valid for 7 days."
