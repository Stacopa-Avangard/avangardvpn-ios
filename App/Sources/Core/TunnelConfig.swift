//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  TunnelConfig.swift — assemble the tunnel config locally.
//
//  The server hands back its half (its public key, endpoint, the assigned
//  address, the PSK); the private key never leaves this device, so the complete
//  config only ever exists here.
//
//  ⚠️ There is deliberately no wg-quick text form here. This file used to
//  build one, on the belief it was "what WireGuardKit's parser consumes". That
//  was wrong — the wg-quick parser lives in wireguard-apple's WireGuardApp
//  target, not in the `WireGuardKit` library product, so nothing in the
//  extension could ever read it. The tunnel is handed a `TunnelProfile`:
//  structured values, no text format in the middle.
//
//  It survived that discovery only because the account screen displayed it.
//  That panel is gone (it read as "this is WireGuard", which is not how the
//  product presents itself), and with it the last reason to assemble a private
//  key into plaintext anywhere in this app. Don't reintroduce one: the profile
//  path already carries every field, `PersistentKeepalive` included.
//
import Foundation

struct TunnelConfig: Equatable {
    let privateKey: String
    let addresses: [String]
    let dns: [String]
    let serverPublicKey: String
    let presharedKey: String
    let allowedIps: [String]
    let endpoint: String

    /// Build from a provisioning response plus this device's private key.
    ///
    /// The IPv6 rule is load-bearing: `::/0` is routed **only** when the server
    /// actually assigned a v6 address. A tunnel that captures all v6 traffic
    /// without holding a v6 address black-holes it — the packets go into the
    /// tunnel and can never be sourced. That is why `assignedIpv6 == nil` also
    /// strips every v6 entry out of AllowedIPs rather than just skipping the
    /// address.
    init(privateKey: String, region: DeviceRegionResponse) {
        self.privateKey = privateKey
        self.serverPublicKey = region.serverPublicKey
        self.presharedKey = region.presharedKey
        self.endpoint = region.endpoint

        var addresses = ["\(region.assignedIp)/32"]
        if let v6 = region.assignedIpv6 {
            addresses.append("\(v6)/128")
        }
        self.addresses = addresses

        self.dns = Self.split(region.dns)

        let advertised = Self.split(region.allowedIps)
        self.allowedIps = region.assignedIpv6 == nil
            ? advertised.filter { !$0.contains(":") }
            : advertised
    }

    /// What actually reaches the tunnel extension, via
    /// `NETunnelProviderProtocol.providerConfiguration`. Same values as
    /// Everything the extension needs — see TunnelProfile.swift.
    var profile: TunnelProfile {
        TunnelProfile(
            privateKey: privateKey,
            addresses: addresses,
            dns: dns,
            serverPublicKey: serverPublicKey,
            presharedKey: presharedKey,
            allowedIps: allowedIps,
            endpoint: endpoint
        )
    }

    private static func split(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
