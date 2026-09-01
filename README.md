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
  **Enrolment in progress as of 2026-09-02**; not yet usable for this app. This
  is what blocks P3-on-device, P5, and P6. A free Apple ID cannot carry the
  `packet-tunnel-provider` entitlement, so there is no workaround — everything
  else was built so it could land without waiting on it.
- App IDs + capabilities: **Network Extensions** (packet-tunnel-provider) + **App Groups** on both bundle IDs.
- Signing via `fastlane match` (for CI) or Xcode automatic signing (local).
- App icon: present, see [Icon](#icon).

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
phone**, the assembled config, account + quota screens.

⚠️ **Connect does not work in this scheme**, and that is not the same as it
being unimplemented. `AvangardVPNDeviceTest` deliberately omits the tunnel
extension and the App Group, because a free Personal Team cannot sign either.
The tunnel is built (P3); it needs the paid entitlement to run.

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

## Icon

`App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, generated
by [`Tools/render-app-icon.swift`](Tools/render-app-icon.swift):

```bash
swift Tools/render-app-icon.swift \
  App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

It draws the brand kit's "A" monogram — the exact `pathData` from Android's
`ui/src/main/res/drawable/ic_launcher_foreground.xml`, in its native 250×250
viewport — on Android's launcher gradient (`#312E81` → `#0D6EFD`, top-left to
bottom-right). Nothing is upscaled: the glyph is vector all the way to the
1024 raster, which is why the script exists instead of a checked-in export from
a design tool.

Two things it does that are not obvious, and that a hand-made replacement would
get wrong:

- **No alpha channel** (`noneSkipLast`). App Store Connect rejects an app icon
  that carries one.
- **The glyph is 62% of the canvas, where Android's reads as ~78%.** Android's
  is a 108dp adaptive icon of which only 72dp is ever visible, so the same
  optical weight needs a smaller fraction on iOS, where the whole 1024 shows.

The shield is a different mark and is not the app icon on either platform: it
is the splash and the sign-in screen (`SplashView`, `ShieldMark`).

## Design

The interface is a **port of the Android client's design system**, not a
separate iOS look. `App/Sources/Design/Theme.swift` mirrors Android's
`ui/theme/Theme.kt` value for value: the `#090B12` ground, the indigo → amber →
emerald ramp that the connection phase drives, the glass treatment, the ambient
wash behind every screen.

Two rules follow from that, and both have already been broken once:

- **A palette change lands on both clients or neither.** iOS used to paint its
  controls `#0D6EFD` under a comment claiming that was Android's primary. It is
  not — it is the launcher-icon blue, and Android's UI primary is `#6366F1`.
  The two clients looked like different products for it.
- **Byte counts are base 1000** (`Core/ByteFormat.swift`), matching the backend
  and the portal. iOS used to call `ByteCountFormatter` with `.binary`, so a
  10 GB plan read as "9.3 GB" here and "10.0 GB" everywhere else.

The shell is a `ZStack`, not a `TabView`: the ambient wash has to sit behind
everything and the glass nav bar has to float over it, and a system tab bar
paints an opaque strip over the bottom glow.

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

  ⚠️ This applies to **running the app in the Simulator too**, not only to the
  tests, and it fails in a way that does not look like a signing problem: the
  build succeeds, the app launches, and sign-in ends on *"Couldn't save your
  session to the Keychain."* Drop the flag and rebuild. CI can pass it because
  CI only compiles and runs tests that do not touch the Keychain.
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
- [x] **P3** — Tunnel: `PacketTunnelProvider` + WireGuardKit (wireguard-go build).
      **Code complete and CI-green, not yet exercised on a phone** — that needs
      the packet-tunnel entitlement, which needs the paid account. Treat the
      connect path as unverified until someone has watched it come up.
- [x] **P4** — SwiftUI UI: Connect / Account tabs, region picker sheet, quota
      meter, shared theme tokens. The connect control is live.
- [x] **P4.5** — Design parity with Android: the "security console" system is
      now a port rather than a lookalike — same palette, same phase→accent ramp,
      same orb, glass, floating nav and telemetry strip. See *Design* below.
- [ ] **P5** — Always-on (`NEOnDemandRule`). IPv6 dual-stack (`assignedIpv6`) is
      **already done** — `TunnelConfig` routes `::/0` only when the region
      assigns a v6 address. On-demand is deliberately off (see
      `VPNConfiguration.apply`): it is a product decision on a metered plan, and
      it would reconnect after a user had deliberately disconnected.
- [ ] **P6** — TestFlight distribution

### Still missing, and why it matters

- **Nothing blocks review any more on the account side**: in-app account
  deletion (Guideline 5.1.1(v)), sign-in by code for the reviewer, and in-app
  privacy/terms links all landed with P4.5.
- The **paid Apple Developer Program enrolment** is the remaining gate. It
  blocks P3-on-hardware, P5 and P6, and there is no workaround — a free Apple ID
  cannot carry `packet-tunnel-provider`.
