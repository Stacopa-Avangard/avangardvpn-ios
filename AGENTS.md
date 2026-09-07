# AGENTS.md

Instructions for coding agents working in this repository (`Stacopa-Avangard/avangardvpn-ios`).

## Project context

Native **iOS client** for **AvangardVPN**, a personal WireGuard-based VPN. It mirrors the Android client (`Stacopa-Avangard/avangardvpn-android`) and talks to the **same backend** (`Stacopa-Avangard/avangardvpn-server`) with **zero backend changes**.

Backend: `https://app.avangardvpn.com`. The base URL is the only environment-specific value in the client; it lives in `Core/AppConfig.swift` and nowhere else.

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

Pinning to a revision rather than a branch is deliberate: a moving branch would change the tunnel's cryptography without a review. Any move to a different upstream is an **audit, not a swap** — variants carry extra features (multihop, DAITA, TCP-in-tunnel) and at least one that shifts network-settings responsibility to the caller, which would bring our provider up with no routes.

## The app sells nothing

⛔ There are no purchase flows in this client, and that is deliberate, not an
unfinished feature. None of these may be added: a "Renew" / "Top up" / "Buy"
control of any kind (including one that only opens a browser), a price anywhere,
plan comparisons, upsell cards, promotional banners, or a push notification
inviting a purchase.

The one that gets added by accident is an out-of-quota message that *suggests
what to do about it*, because it reads as helpfulness. The safe wording is the
one `NearQuotaBanner` already carries: **"You've hit your monthly limit. The VPN
is paused until it resets."** It states what happened and recommends no remedy.

Facts are fine: remaining quota, an expiry date, "paused until it resets".
Signing in and managing an existing account is fine.

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
