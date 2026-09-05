# AGENTS.md

Instructions for coding agents working in this repository (`Stacopa-Avangard/avangardvpn-ios`).

## Project context

Native **iOS client** for **AvangardVPN**, a personal WireGuard-based VPN. It mirrors the Android client (`Stacopa-Avangard/avangardvpn-android`) and talks to the **same backend** (`Stacopa-Avangard/avangardvpn-server`) with **zero backend changes**.

Backend: `https://app.avangardvpn.com` (canonical). It answers to a second name, `https://vpn.stacopa-avangard.com`, which is a permanent alias onto the identical origin. ⛔ **That alias can never be retired** — every shipped Android build compiled it in and its in-app updater reads `/api/version` there.

Three targets in one XcodeGen project: the app, the `NEPacketTunnelProvider` extension, and a device-test app. See [`README.md`](README.md) for architecture and the step-by-step guides.

## Current state — 2026-09-02

- Apple Developer Program **paid**; Organization verification passed for `PT Stacopa Avangard Raya`, Team ID **`8HSUX5T86H`**.
- Both App IDs registered with **Network Extensions + App Groups**: `com.avangard.vpn` and `com.avangard.vpn.network-extension`, both bound to App Group `group.com.avangard.vpn`.
- P0–P4.5 done. App icon and both privacy manifests are in and asserted by CI on the built `.app`. The **export declaration is deliberately NOT in the plist** — `76d8ee9` moved it to App Store Connect after `ITMS-90592`, so the CI assertion that still demands `ITSAppUsesNonExemptEncryption` is stale and would fail the build if Actions ever ran again. See [`EXPORT-COMPLIANCE.md`](EXPORT-COMPLIANCE.md).
- **No In-App Purchase** — decided 2026-09-02. The app sells nothing and may not promote what the website sells; see § *Monetisation* below before touching the Account or Home screens.
- ✅ **The tunnel ran on a phone, 2026-09-03.** iPhone 12, iOS 26.6, region Singapore. Verified from the outside rather than from the app's own UI: iOS system daemons (`cloudd`, `apsd`, `featureaccessd`) routed over `utun5` with *completed* HTTPS transactions (`err=F`, real response bodies), and the phone's public IP was Singapore. Build `1.0 (1)` is on TestFlight.
- ✅ **The tunnel works on a *distribution* build.** Reported by the operator 2026-09-04: build `1.0 (1)` from TestFlight, connected to **both** Singapore and Germany, no problems. That is the entitlement-class risk closed — `get-task-allow = false` and an Apple Distribution signature would have stopped the tunnel coming up at all, the way the Keychain bug of 2026-09-02 did. ⚠️ Weaker evidence than the 2026-09-03 development test, which was instrumented: this one is a person saying it connected, not a captured log with a completed transaction (`err=F`). If a tunnel fault is ever suspected on a shipped build, re-run the `idevicesyslog` recipe rather than leaning on this line. It carries to build `1.0 (2)`: `git diff 5bc8269 387d49e` touches `Tunnel/`, `Shared/` and `App/Sources/Tunnel/` **not at all** — only the disclosure screen, the entry-point routing and the version keys.
- ✅ **Reviewer sign-in credentials are known.** `<akun demo reviewer — lihat catatan operator>`, proven against production 2026-09-03 and present in App Store Connect 2026-09-04 with `demoAccountRequired: true` — on `betaAppReviewDetail` **and** `appStoreReviewDetail`, which are separate resources. The code is stored only as a sha256 hash and cannot be recovered: write it down when you rotate it, and update both records in the same breath.
- ⬜ **Export compliance is wrong in App Store Connect, and locked.** Both builds read `usesNonExemptEncryption: false`; this app is closed-source and ships its own crypto in `wireguard-go`, so `true` is the accurate answer. ⛔ The field is **write-once** — a PATCH on either build returns `409 "You cannot update when the value is already set."`, so neither can be corrected. Decided 2026-09-04 to leave them and let them expire. The build that is actually submitted for review must be answered `true` **while the field is still `null`**. Read [`EXPORT-COMPLIANCE.md`](EXPORT-COMPLIANCE.md) first, and do not "fix" it by putting the key back in the plist.

## ⛔ Four things that must not be "fixed"

Each of these looks like an oversight and is not. Three were paid for once already.

1. **Go is pinned to `1.21`, not latest.** The wireguard-go bridge's Makefile patches the Go runtime with `goruntime-boottime-over-monotonic.diff` so its monotonic clock follows boot time — that is what keeps WireGuard's handshake and keepalive timers alive while the phone sleeps. The patch was written against Go 1.17–1.21. A newer Go is a **silent** failure: the tunnel looks up and dies overnight. `brew install go` is therefore the wrong instruction, and Homebrew cannot help anyway — `go@1.21` is a *disabled* formula. Use the go.dev archive.
2. **The tunnel builds for `iphoneos`, never the Simulator.** A packet-tunnel extension cannot run in the Simulator at all, and upstream's Makefile has no `iphonesimulator` case — it silently produces a macOS `libwg-go.a` and the link fails on `_darwin_arm_init_mach_exception_handler`.
3. **`AvangardVPNDeviceTest` hosts the unit tests.** It is the only host that can run on a Simulator, because it embeds no extension. Deleting the target takes the whole test suite with it. Its `PRODUCT_MODULE_NAME` is `AvangardVPN` so `@testable import AvangardVPN` keeps working.
4. **`xcodebuild` gets `-scheme`, never `-target`.** It refuses `-target` whenever `-derivedDataPath` is also given, and `-derivedDataPath` is what keeps the SPM checkouts on a cacheable path.

## Entitlements — the app carries the extension's

The **app** target declares `com.apple.developer.networking.networkextension: [packet-tunnel-provider]`, identical to the extension. That is not a copy-paste slip: `NETunnelProviderManager` is gated on that entitlement **at the calling side too**, and without it `saveToPreferences` fails and the tunnel can never start.

⛔ It is **not** `com.apple.developer.networking.vpn.api` ("Personal VPN"/`allow-vpn`) — that is for `NEVPNManager` driving the built-in IKEv2 stack, which this app does not use. Verified against upstream `wireguard-apple`'s own entitlements, which carry networkextension + app-groups and no `vpn.api` key at all.

## The WireGuardKit fork

`packages:` points at **our fork** `Stacopa-Avangard/wireguard-apple`, pinned **by revision**, because upstream's `Package.swift` declares tools-version 5.3 while using `.iOS(.v15)` — SwiftPM refuses the package outright. The fork is 2 files, +2 −1.

⚠️ **Debt to settle before real users:** the fork is frozen on Feb-2023 dependencies including `golang.org/x/crypto v0.6.0`. No known advisory touches WireGuard's usage, but the distance is unmanaged. `mullvad/wireguard-apple`'s `mullvad-master` is the candidate — but moving needs an **audit, not a swap**: it carries multihop, DAITA, TCP-in-tunnel, and a "Stop configuring tunnel settings" commit that may move network-settings responsibility to the caller. If it does, our provider comes up **with no routes**.

## Release artifacts — what breaks quietly

All three fail the same way: **build green, upload rejected.** CI asserts them on the built `.app`; keep that step.

- **Two `PrivacyInfo.xcprivacy` files**, one per bundle, because Apple scans each binary. The app declares email + account id + device UUID and `UserDefaults` (`CA92.1`). The extension declares **nothing collected** and system boot time (`35F9.1`).
  ⛔ **Do not delete the extension's boot-time declaration because grepping `Tunnel/Sources` finds nothing.** It is there for **wireguard-go**, whose timers run on a monotonic clock that is `mach_absolute_time` on Darwin. Apple's scanner reads symbols, not intent.
- **`CFBundleIconName` is pinned in `project.yml`**, on both app targets, because actool on Xcode 26 writes it only *inside* `CFBundleIcons > CFBundlePrimaryIcon` and leaves the top level empty — and ITMS-90713 is about the top-level key. Its value must stay equal to `ASSETCATALOG_COMPILER_APPICON_NAME`.
- **`ITSAppUsesNonExemptEncryption: true`** is the accurate answer, not the cautious one. `false` would be a false declaration: this app embeds wireguard-go's own ChaCha20-Poly1305, Curve25519 and BLAKE2s, so the "encryption available in the operating system" exemption does not apply.

### Export compliance — the smaller version

An earlier draft of the docs claimed the BIS filing blocks TestFlight. **It does not.** Verified 2026-09-02:

- **No ERN** — BIS removed the encryption-registration requirement in its rule of 29 March 2021.
- **Probably no CCATS** — Apple requires one only for *proprietary* algorithms no standards body accepts; every primitive here is an IETF RFC. This is the one judgement worth a professional opinion, and it is labelled as a judgement rather than a fact.
- **France declaration** only if the app is sold on the French App Store.
- **The annual ECCN 5D002 self-classification report is retrospective** — due 1 February for the *previous* calendar year, and not owed at all for a year with no exports.

The only export step before a release is App Store Connect's questionnaire.

## Monetisation — the app sells nothing, on purpose

Decided 2026-09-02: **Option A, no In-App Purchase.** The app is a free
stand-alone companion to a paid web service; every purchase happens on
`app.avangardvpn.com`. That is a policy position, not an unfinished feature.

Two App Store rules stack here, and the VPN-specific one is the stricter:

- **3.1.3(f) Free Stand-alone Apps** lets a free companion to a paid web tool
  skip IAP *"provided there is no purchasing inside the app, or calls to action
  for purchase outside of the app."*
- **5.4 VPN Apps** goes further: a VPN app must *"be free on the App Store"* and
  must *"not display prominent promotions for paid services in the VPN app
  itself."* That bans promotion, not merely purchase links — a plan-comparison
  banner with no button still breaks it.

Neither escape hatch reaches us: the 0% external-link allowance from Epic v.
Apple is **US storefront only**, and the DMA rates are EU only. Indonesia gets
neither.

### What this forbids

⛔ When billing is switched on, none of these may enter the iOS app:

1. A "Renew" / "Top up" / "Buy" control of any kind, including one that merely
   opens a browser
2. A price, anywhere
3. Plan comparisons, upsell cards, promotional banners
4. Push notifications inviting a purchase
5. An out-of-quota message that *suggests what to do about it*

Number 5 is the one that gets added by accident, because it reads as
helpfulness. The safe wording is the one `NearQuotaBanner` already carries:
**"You've hit your monthly limit. The VPN is paused until it resets."** It states
what happened and recommends no remedy. Keep it that way.

### What it allows

Facts are fine: remaining quota, an expiry date, "paused until it resets".
Signing in and managing an existing account is fine. So is redeeming a voucher,
as long as it is redeemed and not bought.

And the useful one, straight from the 3.1.3 preamble: *"Developers can send
communications outside of the app to their user base about purchasing methods
other than in-app purchase."* So the renewal reminder is an **email** sent by the
backend. The app stays silent; the email does the talking.

⚠️ The legal links resolve to `AppConfig.baseURL` + `/privacy` and `/terms`. Once
that site has a pricing page, check those two pages do not carry a "Buy" item in
their navigation — reviewers occasionally read that as steering.

Adding StoreKit later is additive and breaks nothing. IAP was not skipped over
the 15%; it was skipped because the tunnel was unproven on hardware at the time,
and two unverified things at once is one too many. The tunnel is proven now, so
that particular reason has expired — the monetisation reasoning above has not,
and it is the one that governs.

## Naming

The product is **`AvangardVPN`**, one closed-up word, as in ExpressVPN or NordVPN. That is `CFBundleDisplayName`, the sign-in title, the splash accessibility label, and the VPN profile name under Settings.

⛔ `AvangardVPNDeviceTest` deliberately stays **`Avangard Dev`**. The target exists to be unmistakable next to the real app on the same phone, and the branded spelling truncates to `AvangardVPN…` on the Home Screen — exactly the confusion the separate name prevents.

⛔ **Never** use the word "WireGuard" in the app name, bundle id, icon, or any primary branding string. It is a registered trademark; describing the protocol in prose is fine.

## Conventions

- **`project.yml` is the source of truth.** The `.xcodeproj`, `Info.plist`s and `.entitlements` are generated and gitignored — never edit or commit them.
- **Branch → PR → CI green → merge.** CI (`ios-build.yml`) builds app + tunnel for the device, builds the device-test target, and runs the offline tests. `ios-release.yml` is manual/tag-only and uploads to TestFlight; **it has never been run** and needs five repository secrets first.
- Test runs must **not** pass `CODE_SIGNING_ALLOWED=NO` — the Keychain rejects unsigned bundles (`errSecMissingEntitlement`, -34018). Simulator ad-hoc signing is enough.
- Never commit certificates, `.p12`, `.p8`, `.mobileprovision` or API keys. Secrets go to GitHub via `gh secret set` reading from a file, never pasted into a shell, a commit or a chat.
- The server holds **no private key**. Keys are generated on device and stay in the Keychain. Do not reintroduce any path where the server generates or returns one.
- Byte counts are **base 1000** (`Core/ByteFormat.swift`), matching the backend, the portal and Android. `ByteCountFormatter` with `.binary` is how "10 GB" became "9.3 GB" here once already.
- The design system is a **port of Android's**, not a lookalike. A palette change lands on both clients or neither; `Theme.swift` mirrors `ui/theme/Theme.kt` value for value.

## Where to start

For getting the app onto a phone, read [`README.md`](README.md) § **"▶ Running it on a real iPhone (paid account) — start here"**. It is self-contained and carries the known failure modes, including the two whose error messages point somewhere other than the cause.
