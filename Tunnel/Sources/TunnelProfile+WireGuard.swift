//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  TunnelProfile+WireGuard.swift — map our config onto WireGuardKit's types.
//
//  Tunnel-only on purpose. WireGuardKit is linked into the extension and not
//  into the app: the app has no need for it (keys are generated with CryptoKit
//  in App/Sources/Core/WireGuardKey.swift), and linking it there would drag the
//  wireguard-go static library into the app binary for nothing.
//
//  Every initialiser used below is failable, and none of them is failing over
//  something cosmetic — a key that is not valid base64, an address that is not
//  CIDR, an endpoint without a port. Returning nil rather than force-unwrapping
//  means a malformed profile stops the tunnel from starting with a clear error
//  instead of trapping inside the extension, where a crash reads to the user as
//  "VPN turned itself off" and leaves nothing to look at.
//
import Foundation
import WireGuardKit

extension TunnelProfile {
    /// nil when any field cannot be parsed into WireGuardKit's representation.
    var wireGuardConfiguration: TunnelConfiguration? {
        guard
            let privateKey = PrivateKey(base64Key: privateKey),
            let serverKey = PublicKey(base64Key: serverPublicKey)
        else { return nil }

        var interface = InterfaceConfiguration(privateKey: privateKey)

        // compactMap would silently drop a malformed entry and bring the tunnel
        // up with a narrower address set than the server assigned — which looks
        // like working software right up until the traffic it was meant to
        // carry goes somewhere else. Count instead, and refuse.
        let parsedAddresses = addresses.compactMap { IPAddressRange(from: $0) }
        guard parsedAddresses.count == addresses.count else { return nil }
        interface.addresses = parsedAddresses

        // DNS is the exception: a resolver we cannot parse is worth dropping,
        // because the alternative is refusing a tunnel that would otherwise
        // carry traffic perfectly well.
        interface.dns = dns.compactMap { DNSServer(from: $0) }

        var peer = PeerConfiguration(publicKey: serverKey)

        // Absent is different from unparseable. An empty PSK means "no PSK",
        // but a non-empty one we cannot decode means the server said something
        // we did not understand — and starting without it would quietly drop a
        // layer of protection the server believes is in place.
        if !presharedKey.isEmpty {
            guard let psk = PreSharedKey(base64Key: presharedKey) else { return nil }
            peer.preSharedKey = psk
        }

        let parsedAllowed = allowedIps.compactMap { IPAddressRange(from: $0) }
        guard parsedAllowed.count == allowedIps.count else { return nil }
        peer.allowedIPs = parsedAllowed

        guard let endpoint = Endpoint(from: endpoint) else { return nil }
        peer.endpoint = endpoint
        peer.persistentKeepAlive = persistentKeepalive

        return TunnelConfiguration(name: "Avangard", interface: interface, peers: [peer])
    }
}
