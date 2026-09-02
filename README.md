# AvangardVPN — iOS

Native iOS client for **AvangardVPN**, mirroring the Android app
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
  ✅ **Paid 2026-09-02.** Apple only sends the payment link once Organization
  verification passes, so this also confirms `PT Stacopa Avangard Raya` cleared
  verification. `DEVELOPMENT_TEAM` is set in [`project.yml`](project.yml); a
  Team ID is not a secret, and leaving it blank meant `xcodegen generate` wiped
  the team from the project on every run.
- App IDs + capabilities: **Network Extensions** (packet-tunnel-provider) + **App Groups**
  on **both** bundle IDs — `com.avangard.vpn` and `com.avangard.vpn.network-extension` —
  plus the App Group `group.com.avangard.vpn`, which has to exist *before* either App ID can
  reference it. The extension needs both capabilities too: `NETunnelProviderManager` is gated
  on `packet-tunnel-provider` at the calling side as well as the providing side.

  On iOS this is self-serve — enabling the capability is enough, with no entitlement request
  to Apple. (The `networkextension@apple.com` request route is for macOS system extensions
  and content filters.)
- Signing via `fastlane match` (for CI) or Xcode automatic signing (local).

Three upload requirements are already met and needed **none** of the above —
app icon (see [Icon](#icon)), privacy manifest, and the export-compliance
declaration (both under
[Privacy manifest and export compliance](#privacy-manifest-and-export-compliance)).
The only export step left before a release is App Store Connect's own
questionnaire; the BIS filing that section describes looks backwards and is not
owed until the February after the app has actually shipped.

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

One thing the catalog does **not** do on its own, found by the CI check added
alongside the privacy manifests: on Xcode 26 actool writes `CFBundleIconName`
only inside `CFBundleIcons` > `CFBundlePrimaryIcon` and leaves the **top level**
empty — and the top-level key is the one **ITMS-90713** is about. `project.yml`
pins it explicitly on both app targets. Keep its value equal to
`ASSETCATALOG_COMPILER_APPICON_NAME`.

## Privacy manifest and export compliance

App Store requirements that say nothing about how the app behaves and everything
about whether a build can be uploaded at all. Both were done without an Apple
account; neither was ever waiting on the enrolment.

### `PrivacyInfo.xcprivacy` — one per bundle, not one per project

- [`App/Resources/PrivacyInfo.xcprivacy`](App/Resources/PrivacyInfo.xcprivacy)
- [`Tunnel/Resources/PrivacyInfo.xcprivacy`](Tunnel/Resources/PrivacyInfo.xcprivacy)

Mandatory since May 2024, and its absence is not a warning: App Store Connect
answers the upload with **ITMS-91053** and the build never becomes submittable.

Two files, because Apple scans each **binary** and the two give different
answers:

| | App | Tunnel extension |
|---|---|---|
| Collects | email, account id, device UUID — all linked to the user, none for tracking | **nothing** |
| Required-reason API | `UserDefaults` (`CA92.1`) — the active region code | system boot time (`35F9.1`) |

The extension's is the surprising one. Nothing in `Tunnel/Sources` asks for the
boot time — **wireguard-go** does. Its handshake and keepalive timers run on a
monotonic clock, and the Go runtime's `nanotime` on Darwin is
`mach_absolute_time`. Apple's scanner reads symbols, not intent, so grepping our
Swift and finding nothing is not evidence that the declaration is stale.

Deliberately **not** declared: `deviceName`. On iOS 16+ — and 16.0 is the floor
here — `UIDevice.current.name` returns the model string without a special
entitlement, so what reaches the server is "iPhone" and it identifies nobody.

### `ITSAppUsesNonExemptEncryption: true`

Set in [`project.yml`](project.yml) on the app target. **True is the accurate
answer, not the cautious one.** The exemption apps normally claim is "only uses
encryption available in the operating system", which fits an app whose crypto is
HTTPS through `URLSession`. It does not fit one that embeds wireguard-go's own
ChaCha20-Poly1305, Curve25519 and BLAKE2s. Nor do the others — authentication,
DRM, medical. A VPN is the textbook non-exempt case.

⚠️ **The declaration opens an obligation — a smaller and later one than the
first version of this section claimed.** Checked against BIS and Apple on
2026-09-02:

| | Status |
|---|---|
| Encryption registration (**ERN**) | **Gone.** BIS removed it in its rule of 29 March 2021 — nothing to register before exporting. |
| **CCATS** | **Probably not needed.** Apple requires one only for *proprietary* algorithms no standards body accepts. Every primitive here is an IETF RFC — ChaCha20-Poly1305 (8439), Curve25519 (7748), BLAKE2s (7693) — Apple's "industry standard algorithm, not provided within the Apple operating system" row. |
| **France declaration** | Only if the app is sold on the French App Store. An Indonesia-only release owes nothing. |
| **Annual self-classification report** | **Retrospective, not a precondition.** ECCN 5D002 under License Exception ENC §740.17(b)(1), due 1 February for the *previous* calendar year and not owed at all for a year with no exports. CSV, 12 columns, to `crypt@bis.doc.gov` and `enc@nsa.gov`. |

So the only export step between here and a release is **App Store Connect's own
questionnaire**. US export rules apply at all because the App Store distributes
from the US — an Indonesian developer account does not change that.

The CCATS row is the one judgement worth a professional opinion: if anyone reads
wireguard-go's protocol as proprietary rather than standard, a CCATS is a BIS
submission with a waiting period attached.

`AvangardVPNDeviceTest` carries neither the key nor the obligation: it is a
free-signed local build that never reaches App Store Connect.

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
- [ ] **P6** — TestFlight distribution. Gated on the enrolment, and on
      answering App Store Connect's export questionnaire — see
      [`ITSAppUsesNonExemptEncryption`](#itsappusesnonexemptencryption-true).

### Still missing, and why it matters

- **Nothing blocks review any more on the account side**: in-app account
  deletion (Guideline 5.1.1(v)), sign-in by code for the reviewer, and in-app
  privacy/terms links all landed with P4.5.
- **Nothing blocks upload any more either**: the app icon landed with P4.5, and
  the privacy manifest and export-compliance declaration with the PR after it.
  All three answer an upload *rejection* rather than a review note, and none of
  them needed an Apple account — which is precisely why the earlier wording here
  ("the enrolment is the remaining gate") was wrong and worth correcting: it
  would have let two of them sit unnoticed until a build bounced.
- **One open item is paperwork rather than code, and it is smaller than it
  first looked here.** Declaring non-exempt encryption puts us under License
  Exception ENC, whose annual ECCN 5D002 report covers **the previous year's
  exports** — so nothing is owed until the app has actually shipped. What is
  needed *before* release is App Store Connect's export questionnaire, plus a
  French declaration only if France is a market. See
  [Privacy manifest and export compliance](#privacy-manifest-and-export-compliance).
- The **paid Apple Developer Program enrolment** is the remaining *engineering*
  gate. It blocks P3-on-hardware, P5 and P6, and there is no workaround — a free
  Apple ID cannot carry `packet-tunnel-provider`.
