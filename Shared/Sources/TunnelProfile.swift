//
//  TunnelProfile.swift — the config the app hands to the tunnel extension.
//
//  Compiled into BOTH targets (see `Shared/Sources` in project.yml). The app
//  writes one of these into `NETunnelProviderProtocol.providerConfiguration`;
//  the extension reads it back and turns it into WireGuardKit's own types (see
//  Tunnel/Sources/TunnelProfile+WireGuard.swift, which is tunnel-only because
//  WireGuardKit is linked only there).
//
//  ⚠️ Why a dictionary and not the wg-quick text TunnelConfig already produces:
//  WireGuardKit's SPM product does NOT ship a wg-quick parser. That parser is
//  `Sources/Shared/Model/TunnelConfiguration+WgQuickConfig.swift` in
//  wireguard-apple, which belongs to the WireGuardApp target, not to the
//  `WireGuardKit` library product. Verified against the published sources on
//  2026-08-31: `Sources/WireGuardKit/` holds twelve files and that is not one
//  of them. TunnelConfig.swift used to claim otherwise in a comment; it was
//  wrong, and building on it would have failed at link time in the extension.
//
//  Passing structured values is the better shape anyway — no text format in the
//  middle means no parser to disagree with the generator.
//
import Foundation

struct TunnelProfile: Equatable {
    let privateKey: String
    let addresses: [String]
    let dns: [String]
    let serverPublicKey: String
    let presharedKey: String
    let allowedIps: [String]
    let endpoint: String

    /// Mobile clients sit behind NAT that drops idle UDP mappings; this keeps
    /// the path open so the server can reach the peer again after a quiet spell.
    let persistentKeepalive: UInt16

    init(
        privateKey: String,
        addresses: [String],
        dns: [String],
        serverPublicKey: String,
        presharedKey: String,
        allowedIps: [String],
        endpoint: String,
        persistentKeepalive: UInt16 = 25
    ) {
        self.privateKey = privateKey
        self.addresses = addresses
        self.dns = dns
        self.serverPublicKey = serverPublicKey
        self.presharedKey = presharedKey
        self.allowedIps = allowedIps
        self.endpoint = endpoint
        self.persistentKeepalive = persistentKeepalive
    }

    // MARK: - providerConfiguration

    /*
      Keys are spelled out rather than derived from property names. This
      dictionary crosses a process boundary and is persisted by the system
      inside the saved VPN configuration, so a rename on either side has to be
      a deliberate act — not a side effect of tidying a property name. A
      mismatch here fails at runtime, in the extension, where it surfaces as a
      tunnel that will not start rather than as a compile error.
    */
    enum Key {
        static let privateKey = "privateKey"
        static let addresses = "addresses"
        static let dns = "dns"
        static let serverPublicKey = "serverPublicKey"
        static let presharedKey = "presharedKey"
        static let allowedIps = "allowedIps"
        static let endpoint = "endpoint"
        static let persistentKeepalive = "persistentKeepalive"
    }

    /// Plist-safe: strings, arrays of strings, and one integer. Anything richer
    /// would not survive being stored in the VPN configuration.
    var providerConfiguration: [String: Any] {
        [
            Key.privateKey: privateKey,
            Key.addresses: addresses,
            Key.dns: dns,
            Key.serverPublicKey: serverPublicKey,
            Key.presharedKey: presharedKey,
            Key.allowedIps: allowedIps,
            Key.endpoint: endpoint,
            Key.persistentKeepalive: Int(persistentKeepalive),
        ]
    }

    /// Returns nil when a required field is absent or the wrong type, which is
    /// the only sane response inside the extension: a partial tunnel config is
    /// not something to repair by guessing.
    init?(providerConfiguration dict: [String: Any]) {
        guard
            let privateKey = dict[Key.privateKey] as? String,
            let addresses = dict[Key.addresses] as? [String],
            let serverPublicKey = dict[Key.serverPublicKey] as? String,
            let presharedKey = dict[Key.presharedKey] as? String,
            let allowedIps = dict[Key.allowedIps] as? [String],
            let endpoint = dict[Key.endpoint] as? String
        else { return nil }

        // DNS is genuinely optional — a region row may advertise none — so its
        // absence is not a failure, unlike the six above.
        let dns = dict[Key.dns] as? [String] ?? []

        let keepalive = dict[Key.persistentKeepalive] as? Int
        self.init(
            privateKey: privateKey,
            addresses: addresses,
            dns: dns,
            serverPublicKey: serverPublicKey,
            presharedKey: presharedKey,
            allowedIps: allowedIps,
            endpoint: endpoint,
            persistentKeepalive: keepalive.map(UInt16.init(clamping:)) ?? 25
        )
    }
}
