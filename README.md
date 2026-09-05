# AvangardVPN for iOS

A WireGuard VPN client for iPhone. Native Swift and SwiftUI, with the tunnel
running in a `NEPacketTunnelProvider` extension.

This is the source for the app published on the App Store. It is open so that
the two claims that matter can be checked rather than believed: that your
private key is generated on your device and never leaves it, and that the app
collects only the four things it says it collects.

## Features

- **WireGuard**, using the protocol's own cryptography — ChaCha20-Poly1305
  (RFC 8439), Curve25519 (RFC 7748), BLAKE2s (RFC 7693)
- **Keys generated on the device.** The server is sent a public key and never
  holds a private one. There is no code path where it could
- **Server nodes in Asia and Europe**, with full IPv4 and IPv6 on both
- **Up to 3 devices** on one account
- **Passwordless sign-in** by emailed link. No password to store, leak or reuse
- **Delete your account from inside the app**, which removes its peers with it
- **No third-party SDKs.** No advertising, no analytics, nothing that talks to
  anywhere but our own backend

## What the app collects

Four things, and each one earns its place:

| | Why |
|---|---|
| Your email address | to send the sign-in link. There are no passwords |
| Your device's public key | so the tunnel knows which device to route to |
| Total data used | to show how much of your plan's quota is left |
| Time of the last handshake | housekeeping, so idle devices can be released |

And what it does not: **where you connect from** is never written to our
database, **your browsing** is never recorded — no DNS lookups, no domains, no
destination addresses — and none of it is sold, shared or handed to anyone.

The app says this on a screen before you sign in, not only in a policy. The text
is in `App/Sources/Auth/DataDisclosureView.swift`, and it is the same text the
phone shows.

## Privacy and IPv6

IPv6 is enabled on every server rather than quietly disabled. Turning it off is
a common shortcut, and it is also a common way for traffic to escape the tunnel.

## Requirements

- iOS 16.0 or later, iPhone
- An AvangardVPN account. The service is invite-only while it is small

## Building it

See [`docs/BUILDING.md`](docs/BUILDING.md). Two things will otherwise cost you an
afternoon: **Go must be 1.21**, and Xcode resolves it from its own PATH rather
than your shell's.

You can build and run the app with a free Apple ID. The tunnel itself needs a
paid one, because Apple does not offer the NetworkExtension entitlement to free
accounts.

## Architecture

Three targets, defined by [`project.yml`](project.yml) via XcodeGen:

| Target | What it is |
|---|---|
| `AvangardVPN` | the app — SwiftUI, sign-in, on-device keygen, region picker, account |
| `AvangardTunnel` | the `NEPacketTunnelProvider` extension, driven by WireGuardKit |
| `AvangardVPNDeviceTest` | the app minus the extension, so it runs on a Simulator and hosts the tests |

The app and the extension are separate processes and share the tunnel
configuration through the App Group `group.com.avangard.vpn`. `Shared/Sources`
is compiled into both, which is the only way the two sides are guaranteed to
agree on the shape of that configuration.

Tokens and the device private key live in the **Keychain**. Byte counts are
base 1000, matching the backend and the Android client.

## The Android client

[`Stacopa-Avangard/avangardvpn-android`](https://github.com/Stacopa-Avangard/avangardvpn-android)
is the same product on the other platform, talking to the same backend. The
design system here is a port of that one, value for value, rather than a
lookalike — a palette change belongs on both clients or neither.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Contributions are welcome; reading the
source is welcome too, and is the reason this repository is public.

⚠️ Bugs in the app's code belong in the issue tracker. Connection problems,
account questions, quota and billing are not answerable from here.

## Licence

**GPL-3.0-only** — see [`LICENSE`](LICENSE). Every source file carries an
`SPDX-License-Identifier` header.

WireGuard is a registered trademark of Jason A. Donenfeld. This app uses the
WireGuard protocol; it is not affiliated with or endorsed by the WireGuard
project.
