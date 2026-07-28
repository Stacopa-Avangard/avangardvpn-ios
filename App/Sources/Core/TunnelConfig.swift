//
//  TunnelConfig.swift — assemble the tunnel config locally.
//
//  The server hands back its half (its public key, endpoint, the assigned
//  address, the PSK); the private key never leaves this device, so the complete
//  config only ever exists here. Output is `wg-quick` format because that is
//  what WireGuardKit's parser consumes in P3.
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

    /// `wg-quick` INI form — what WireGuardKit parses in P3.
    var wgQuickConfig: String {
        var lines = [
            "[Interface]",
            "PrivateKey = \(privateKey)",
            "Address = \(addresses.joined(separator: ", "))",
        ]
        if !dns.isEmpty {
            lines.append("DNS = \(dns.joined(separator: ", "))")
        }
        lines.append(contentsOf: [
            "",
            "[Peer]",
            "PublicKey = \(serverPublicKey)",
            "PresharedKey = \(presharedKey)",
            "AllowedIPs = \(allowedIps.joined(separator: ", "))",
            "Endpoint = \(endpoint)",
            // Mobile clients sit behind NAT that drops idle UDP mappings; this
            // keeps the path open so the server can reach the peer again after
            // an idle stretch.
            "PersistentKeepalive = 25",
        ])
        return lines.joined(separator: "\n")
    }

    private static func split(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
