# Avangard VPN — iOS

Native iOS client for **Avangard VPN**, mirroring the Android app
(`Stacopa-Avangard/avangardvpn-android`). Talks to the **same backend** (`Stacopa-Avangard/avangardvpn-server`,
`https://app.avangardvpn.com`) — no backend changes needed. That backend answers to a
second name, `vpn.stacopa-avangard.com`, which is a permanent alias onto the identical
origin and cannot be retired — Android compiled it into every shipped build.

## Architecture

Three targets in one Xcode project (defined by [`project.yml`](project.yml), XcodeGen):

| Target | What |
|---|---|
| **AvangardVPN** (app) | SwiftUI UI, poll-login, on-device keygen, region picker; tokens + private key in **Keychain**; API via `URLSession` |
| **AvangardTunnel** (app-extension) | `NEPacketTunnelProvider` — the WireGuard tunnel, driven by **WireGuardKit** (from `wireguard-apple`) |
| **AvangardVPNTests** (unit-test) | Integration tests against a locally-run backend — see [Tests](#tests) |
| App Group `group.com.avangard.vpn` | shares config between app ↔ extension |

- Bundle IDs: app `com.avangard.vpn`, tunnel `com.avangard.vpn.network-extension`
- Min iOS **16.0**; Swift 5.9 / SwiftUI
- The server holds **no private key** — the key is generated on device (CryptoKit) and stays in the Keychain, same as Android.

## Prerequisites (for signed/device builds)

- **Apple Developer Program** ($99/yr) — required for the NetworkExtension entitlement + TestFlight.
  **Not yet provisioned for this app** (as of 2026-07-28), which is what blocks
  P3 on-device, P5, and P6. A free Apple ID cannot carry the
  `packet-tunnel-provider` entitlement, so there is no workaround.
- App IDs + capabilities: **Network Extensions** (packet-tunnel-provider) + **App Groups** on both bundle IDs.
- Signing via `fastlane match` (for CI) or Xcode automatic signing (local).

Everything through P2 (and the UI work in P4) needs none of this — it builds and
tests on the Simulator unsigned.

## Build

The project is **text-defined** (XcodeGen), so it can be authored on any OS and
compiled on macOS.

```bash
# On macOS (or CI):
brew install xcodegen
xcodegen generate            # writes AvangardVPN.xcodeproj (gitignored)
open AvangardVPN.xcodeproj    # develop / run on a device from Xcode
```

**CI** ([`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml)) does an
**unsigned iOS-Simulator build** on a macOS runner — a compile-check that needs **no
Apple account**. (VPN can't actually run in the Simulator — device testing needs a
real iPhone + signing.)

## Trying it on a real iPhone (no paid account)

Everything built so far — sign-in, region provisioning, the UI — uses **no paid
capability**. App Groups and NetworkExtension belong to the tunnel (P3), which
isn't here yet. So the `AvangardVPNDeviceTest` scheme runs the real app on a
real iPhone signed with a **free Apple ID**:

```bash
xcodegen generate && open AvangardVPN.xcodeproj
```

In Xcode: scheme **AvangardVPNDeviceTest** → target → Signing & Capabilities →
*Automatically manage signing* → Team = **your own Personal Team** → select
your iPhone → Run.

Once signing is set up once, re-installing is faster from the CLI — which
matters because free-signed builds expire every 7 days:

```bash
DEVELOPMENT_TEAM=<your-personal-team-id> Scripts/install-on-device.sh
```

It picks the connected device itself, builds, checks the bundle carries no paid
entitlement, and installs. Find your team id with:

```bash
security find-identity -v -p codesigning
security find-certificate -c "<the Apple Development line>" -p \
  | openssl x509 -noout -subject     # OU=... is the team id
```

Two one-time steps on the phone:

- **Settings → Privacy & Security → Developer Mode** → on. iOS 16+ refuses to
  run self-built apps without it, and turning it on reboots the phone. Until
  then the device shows as *available* rather than *connected* and builds fail
  with `Developer Mode disabled`.
- After the first install: **Settings → General → VPN & Device Management** →
  trust the developer certificate.

A **Personal Team is separate from any organisation** the same Apple ID belongs
to — different team id, its own certificate, its own App IDs. Signing with it
registers nothing against the organisation's account.

What works: sign-in, choosing a region, a **real keypair generated on the
phone**, the assembled config, account + quota screens. **Connect stays
disabled** — there is no tunnel yet.

Verified on real hardware 2026-07-28: builds, signs under a Personal Team, and
installs onto an iPhone 12 (iOS). Not yet exercised by a person end-to-end —
in particular, opening the magic link from a real inbox and having the app pick
the session up by polling has still only been tested via scripts.

Two things to know:

- **Free-signed builds expire after 7 days.** Re-run from Xcode to renew.
- The bundle id is `com.avangard.vpn.devtest`, deliberately **not** the
  production `com.avangard.vpn`. App IDs are globally unique across Apple
  Developer accounts, so letting a personal team claim the production id risks
  blocking the real account from registering it later.

By default the app talks to production, so you need an account there. To point
it at a backend on your Mac instead, add `AVANGARD_API_BASE=http://<mac-lan-ip>:3000`
to the scheme's environment variables (Product → Scheme → Edit Scheme → Run →
Arguments) with the phone on the same Wi-Fi. That variable is DEBUG-only and
compiled out of Release builds.

## Tests

`AvangardVPNTests` exercises the real API client against a backend running
locally from `Stacopa-Avangard/avangardvpn-server` — no production traffic, no emails
sent (dev logs the magic link to stdout instead).

```bash
# terminal 1 — in the wireguard-dashboard checkout
cd backend && cp .env.example .env   # fill in throwaway secrets, RESEND_API_KEY empty
pnpm install && pnpm seed:admin -- --email=ios-test@avangard.local --name="iOS Tester"
pnpm dev 2>&1 | tee /tmp/backend.log

# terminal 2 — here
BACKEND_LOG=/tmp/backend.log Scripts/run-auth-tests.sh
```

The script does what a test inside the Simulator can't: it reads the magic-link
token out of the backend log and "clicks" the link, so the test can then claim
the session exactly as the app would.

To poke at the signed-in UI by hand without typing an address and opening a
mail client:

```bash
BACKEND_LOG=/tmp/backend.log Scripts/run-dev-session.sh
```

It prepares a verified session the same way and launches the app already signed
in (the app claims it on launch — DEBUG only, see `AuthStore.restore`). Set
`AVANGARD_DEV_TAB=account` to open straight onto the Account screen.

Two things about how these run, both deliberate:

- **No `CODE_SIGNING_ALLOWED=NO`.** The Keychain refuses to store anything for
  an unsigned bundle (`errSecMissingEntitlement`, -34018), so the tests rely on
  the ad-hoc signature Xcode gives Simulator builds. Still no Apple account.
- Config reaches the tests as **scheme environment variables** fed from build
  settings. The `TEST_RUNNER_`-prefix trick only works for UI-test runners.

Without `AVANGARD_API_BASE` set, the network tests skip themselves, so a plain
`xcodebuild test` (and CI's compile-check) stays green with no backend around.

## Roadmap

- [x] **P0** — repo + XcodeGen scaffold (app + tunnel stub) + CI compile-check
- [x] **P1** — Auth: poll-login (`/auth/poll`), Keychain token store, auto-refresh
      on 401, sign-in UI. Verified end-to-end against a local backend.
- [x] **P2** — Provisioning: Curve25519 keygen (CryptoKit), `POST /api/me/devices/regions`,
      local config assembly, region picker. Verified end-to-end against a local backend.
- [ ] **P3** — Tunnel: `PacketTunnelProvider` + WireGuardKit (wireguard-go build)
- [x] **P4** — SwiftUI UI: Connect / Account tabs, region picker sheet, quota
      meter, shared theme tokens (dark/glass). The connect control is present
      but disabled until P3 lands.
- [ ] **P5** — IPv6 dual-stack (`assignedIpv6`) + Always-on (`NEOnDemandRule`)
- [ ] **P6** — TestFlight distribution
