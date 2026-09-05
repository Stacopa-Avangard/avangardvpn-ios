# AGENTS.md

Instructions for coding agents working in this repository (`Stacopa-Avangard/avangardvpn-ios`).

## Project context

Native **iOS client** for **AvangardVPN**, a personal WireGuard-based VPN. It mirrors the Android client (`Stacopa-Avangard/avangardvpn-android`) and talks to the **same backend** (`Stacopa-Avangard/avangardvpn-server`) with **zero backend changes**.

Backend: `https://app.avangardvpn.com` (canonical). It answers to a second name, `https://vpn.stacopa-avangard.com`, which is a permanent alias onto the identical origin. ⛔ **That alias can never be retired** — every shipped Android build compiled it in and its in-app updater reads `/api/version` there.

Three targets in one XcodeGen project: the app, the `NEPacketTunnelProvider` extension, and a device-test app. See [`README.md`](README.md) for architecture and the step-by-step guides.

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
- **Branch → PR → CI green → merge.** CI (`ios-build.yml`) builds app + tunnel for the device, builds the device-test target, and runs the offline tests.
- Test runs must **not** pass `CODE_SIGNING_ALLOWED=NO` — the Keychain rejects unsigned bundles (`errSecMissingEntitlement`, -34018). Simulator ad-hoc signing is enough.
- ⛔ **No credentials in this repository, ever** — no certificates, no keys, no account addresses, no device identifiers. Signing and release material lives outside it.
- The server holds **no private key**. Keys are generated on device and stay in the Keychain. Do not reintroduce any path where the server generates or returns one.
- Byte counts are **base 1000** (`Core/ByteFormat.swift`), matching the backend, the portal and Android. `ByteCountFormatter` with `.binary` is how "10 GB" became "9.3 GB" here once already.
- The design system is a **port of Android's**, not a lookalike. A palette change lands on both clients or neither; `Theme.swift` mirrors `ui/theme/Theme.kt` value for value.

## Where to start
