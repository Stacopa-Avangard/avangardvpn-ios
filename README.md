# Avangard VPN — iOS

Native iOS client for **Avangard VPN**, mirroring the Android app
(`fixidn/avangard-vpn-app`). Talks to the **same backend** (`fixidn/wireguard-dashboard`,
`https://vpn.stacopa-avangard.com`) — no backend changes needed.

## Architecture

Three targets in one Xcode project (defined by [`project.yml`](project.yml), XcodeGen):

| Target | What |
|---|---|
| **AvangardVPN** (app) | SwiftUI UI, poll-login, on-device keygen, region picker; tokens + private key in **Keychain**; API via `URLSession` |
| **AvangardTunnel** (app-extension) | `NEPacketTunnelProvider` — the WireGuard tunnel, driven by **WireGuardKit** (from `wireguard-apple`) |
| App Group `group.com.avangard.vpn` | shares config between app ↔ extension |

- Bundle IDs: app `com.avangard.vpn`, tunnel `com.avangard.vpn.network-extension`
- Min iOS **16.0**; Swift 5.9 / SwiftUI
- The server holds **no private key** — the key is generated on device (CryptoKit) and stays in the Keychain, same as Android.

## Prerequisites (for signed/device builds)

- **Apple Developer Program** ($99/yr) — required for the NetworkExtension entitlement + TestFlight.
- App IDs + capabilities: **Network Extensions** (packet-tunnel-provider) + **App Groups** on both bundle IDs.
- Signing via `fastlane match` (for CI) or Xcode automatic signing (local).

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

## Roadmap

- [x] **P0** — repo + XcodeGen scaffold (app + tunnel stub) + CI compile-check
- [ ] **P1** — Auth: poll-login (`/auth/poll`), Keychain token store
- [ ] **P2** — Provisioning: Curve25519 keygen, `POST /api/me/devices/regions`, build config
- [ ] **P3** — Tunnel: `PacketTunnelProvider` + WireGuardKit (wireguard-go build)
- [ ] **P4** — SwiftUI UI: Home / Account / region picker (dark/glass)
- [ ] **P5** — IPv6 dual-stack (`assignedIpv6`) + Always-on (`NEOnDemandRule`)
- [ ] **P6** — TestFlight distribution
