#!/usr/bin/env bash
#
# Run the auth integration tests against a locally-running backend.
#
# A test running inside the Simulator cannot read the backend's stdout, and in
# dev the magic-link token is *logged* rather than emailed. So this script does
# the two steps the test can't: it pulls the token out of the log and "clicks"
# the link. The test then claims the session exactly as the app would.
#
# Usage:
#   # terminal 1 — in fixidn/wireguard-dashboard
#   cd backend && pnpm dev 2>&1 | tee /tmp/backend.log
#
#   # terminal 2 — here
#   BACKEND_LOG=/tmp/backend.log Scripts/run-auth-tests.sh
#
set -euo pipefail

API="${AVANGARD_API_BASE:-http://localhost:3000}"
EMAIL="${TEST_EMAIL:-ios-test@avangard.local}"
BACKEND_LOG="${BACKEND_LOG:-}"

if [[ -z "$BACKEND_LOG" || ! -f "$BACKEND_LOG" ]]; then
  echo "error: set BACKEND_LOG to the file the backend's stdout is being written to." >&2
  echo "       (dev logs the magic link there instead of sending email)" >&2
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

# Open a login session and click its emailed link, leaving it in the "verified"
# state — ready for the test to claim.
verified_session() {
  local sid token before

  # Only look at log lines written AFTER this request. The link is emitted
  # asynchronously, so grabbing "the newest token in the file" races: it can
  # return a token from an earlier session, and verifying that one marks the
  # wrong session verified — which shows up much later as a confusing
  # "pending, expected verified" test failure.
  before="$(wc -l < "$BACKEND_LOG")"
  sid="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"

  curl -sf -X POST "$API/auth/request-link" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"loginSessionId\":\"$sid\"}" -o /dev/null

  for _ in $(seq 1 40); do
    token="$(tail -n "+$((before + 1))" "$BACKEND_LOG" \
      | grep -o 'token=[A-Za-z0-9_-]*' | tail -1 | cut -d= -f2)"
    [[ -n "$token" ]] && break
    sleep 0.25
  done

  if [[ -z "$token" ]]; then
    echo "error: no magic-link token appeared in $BACKEND_LOG after the request." >&2
    echo "       is RESEND_API_KEY empty in backend/.env? (dev logs the link instead)" >&2
    exit 1
  fi

  curl -sf "$API/auth/verify?token=$token" -o /dev/null
  echo "$sid"
}

echo "==> preparing verified login sessions for $EMAIL"
SID_CLAIM="$(verified_session)"
SID_REFRESH="$(verified_session)"
SID_PROVISION="$(verified_session)"

echo "==> running tests on simulator $DEVICE_ID"
xcodegen generate >/dev/null

# These are passed as build settings; the scheme forwards them into the test
# process as environment variables (see `environmentVariables` in project.yml).
#
# Note there is no CODE_SIGNING_ALLOWED=NO here, unlike the plain compile-check.
# The Keychain refuses to store anything for an unsigned bundle
# (errSecMissingEntitlement, -34018), so the tests need the ad-hoc signature
# Xcode applies to Simulator builds. No Apple account is involved.
xcodebuild test \
  -project AvangardVPN.xcodeproj \
  -scheme AvangardVPN \
  -destination "id=$DEVICE_ID" \
  AVANGARD_API_BASE="$API" \
  AVANGARD_VERIFIED_SESSION_ID="$SID_CLAIM" \
  AVANGARD_VERIFIED_SESSION_ID_2="$SID_REFRESH" \
  AVANGARD_VERIFIED_SESSION_ID_3="$SID_PROVISION"
