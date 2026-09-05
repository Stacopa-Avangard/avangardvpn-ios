# Building AvangardVPN for iOS

You can build this app from source and run it on your own iPhone. That is the
point of publishing it: you should not have to take our word for what the app
does with your key or your traffic.

Signing it with **your own** Apple account is enough for everything except the
tunnel itself, which needs a paid account because the NetworkExtension
entitlement is not available to free ones. That limit is Apple's, not ours.

## What you need

| | |
|---|---|
| macOS with **Xcode 26** | the project targets iOS 16.0 and builds with Swift 5.9+ |
| **XcodeGen 2.38.0+** | `brew install xcodegen` |
| **Go 1.21**, and only 1.21 | see the warning below — this one matters |

## ⛔ Go must be 1.21

The wireguard-go bridge patches the Go runtime so its monotonic clock follows
boot time. That patch is what keeps WireGuard's handshake and keepalive timers
running while the phone is asleep, and it was written against Go 1.17–1.21. A
newer Go **fails silently**: the app builds, the tunnel comes up, and then it
dies overnight.

Homebrew cannot help — `go@1.21` is a disabled formula. Use the official
archive:

```bash
curl -LO https://go.dev/dl/go1.21.13.darwin-arm64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.13.darwin-arm64.tar.gz
/usr/local/go/bin/go version    # expect go1.21.13
```

⚠️ **Extracting Go is not enough on its own.** The bridge target spawns
`/usr/bin/env make`, so it resolves `go` from **Xcode's** build PATH, not your
shell's. Measured on macOS 26: Xcode adds nothing of its own and
`launchctl getenv PATH` is empty on a stock machine, so a GUI-launched Xcode
builds with exactly `/usr/bin:/bin:/usr/sbin:/sbin`. Neither `/usr/local/go/bin`
nor Homebrew's `/opt/homebrew/bin` is on that list.

Set it once, then log out and back in:

```bash
sudo launchctl config user path /usr/local/go/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

⛔ And the failure does **not** say `go: command not found`. The bridge's
Makefile reads `REAL_GOROOT := $(shell go env GOROOT 2>/dev/null)`, which
swallows the real error, so all you see is:

```
/usr/bin/env make
[ -n "" ]
make: *** [.../wireguard-go-bridge/goroot/.prepared] Error 1
```

## Build

`project.yml` is the source of truth. The `.xcodeproj`, the `Info.plist` files
and the entitlements are all generated from it and are not in git.

```bash
xcodegen generate
open AvangardVPN.xcodeproj
```

In Xcode, set the signing team on each target to your own, then build and run.

## Running it on a device

Choose your target by what you want to see.

**`AvangardVPNDeviceTest`** runs under a **free** Apple ID. It is the real app —
sign-in, region selection, a real keypair generated on the phone, the account
and quota screens — with the tunnel extension and the App Group left out,
because a free Personal Team cannot sign either. Its bundle id is
`com.avangard.vpn.devtest`, deliberately separate.

⚠️ Connect does not work in this scheme. That is not a missing feature; it is
the entitlement.

**`AvangardVPN`** is the whole app and needs a paid account with the
NetworkExtension and App Groups capabilities enabled on both bundle ids.

Two one-time steps on the phone either way:

- **Settings → Privacy & Security → Developer Mode** → on. iOS 16+ refuses to
  run self-built apps without it, and turning it on reboots the phone.
- After the first install: **Settings → General → VPN & Device Management** →
  trust the certificate.

⚠️ Free-signed builds expire after **7 days**. Re-run from Xcode to renew.

## Tests

The suite runs on the Simulator and needs a backend to talk to. Point it at a
local one rather than production:

```bash
AVANGARD_API_BASE=http://localhost:3000 \
  xcodebuild test -scheme AvangardVPNDeviceTest -destination 'platform=iOS Simulator,name=iPhone 16'
```

⚠️ `AvangardVPNDeviceTest` hosts the tests deliberately — it is the only target
that can run on a Simulator, because it embeds no extension. Deleting it takes
the whole suite with it.

⛔ Do **not** pass `CODE_SIGNING_ALLOWED=NO`. The Keychain rejects unsigned
bundles with `errSecMissingEntitlement` (-34018). Simulator ad-hoc signing is
enough.

## Known failure modes

| Symptom | Cause |
|---|---|
| `[ -n "" ]` then `Error 1` from the bridge | Go missing from **Xcode's** PATH, not yours |
| Tunnel works, then dies overnight | Go is newer than 1.21 |
| `_darwin_arm_init_mach_exception_handler` at link | the tunnel was built for the Simulator. It cannot be — upstream's Makefile has no `iphonesimulator` case and silently produces a macOS library |
| `errSecMissingEntitlement` (-34018) in tests | `CODE_SIGNING_ALLOWED=NO` |
| `No provisioning profile found` | a capability is missing on one of the App IDs, most often App Groups |

## Repository layout

| | |
|---|---|
| `App/Sources` | the app: SwiftUI screens, sign-in, on-device keygen, API client |
| `Tunnel/Sources` | the `NEPacketTunnelProvider` extension |
| `Shared/Sources` | the config shape both processes must agree on, compiled into both |
| `Tests` | unit and integration tests |
| `project.yml` | XcodeGen project definition — edit this, never the `.xcodeproj` |
| `Tools/render-app-icon.swift` | renders the app icon from the brand vector |
