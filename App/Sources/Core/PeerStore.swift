//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  PeerStore.swift — per-region peer credentials.
//
//  Keyed by region, not by device, because `peers.public_key` is UNIQUE
//  server-side: registering the same public key for a second region is rejected
//  with `409 public_key_in_use`. So each region gets its own keypair, and this
//  is where the private half lives.
//
//  The provisioning response is stored alongside it — it carries the preshared
//  key, which is a secret too, so it belongs in the Keychain rather than
//  UserDefaults.
//
import Foundation

enum PeerStore {
    /// Credentials are namespaced per user, not just per region.
    ///
    /// Two reasons, and they pull in opposite directions:
    ///
    /// - Sign-out must NOT delete the private key. The backend's registration
    ///   is idempotent per (user, device, region) and returns the *existing*
    ///   peer without updating its public key — so a device that threw its key
    ///   away can never be matched to its own peer again. It would have to
    ///   revoke the device and start over.
    /// - But keeping the key around unscoped means the next user to sign in on
    ///   this device inherits the previous user's region as "ready", pointing
    ///   at their IP and their key.
    ///
    /// Scoping by user id satisfies both: the same user signing back in finds
    /// their key intact, and a different user sees a clean slate.
    private static var scope: String {
        TokenStore.user?.id ?? "anonymous"
    }

    private static func privateKeyKey(_ region: String) -> String {
        "peer.privateKey.\(scope).\(region)"
    }

    private static func regionKey(_ region: String) -> String {
        "peer.region.\(scope).\(region)"
    }

    // MARK: - Private keys

    /// This device's private key for a region, minting one on first use.
    /// Reused across re-registrations so the server keeps matching us to the
    /// same peer row instead of allocating a new IP each time.
    static func privateKey(for region: String) -> String {
        if let existing = try? Keychain.string(for: privateKeyKey(region)) {
            return existing
        }
        let pair = WireGuardKeyPair.generate()
        try? Keychain.set(pair.privateKey, for: privateKeyKey(region))
        return pair.privateKey
    }

    static func publicKey(for region: String) -> String? {
        WireGuardKeyPair.publicKey(forPrivateKey: privateKey(for: region))
    }

    // MARK: - Provisioned regions

    static func save(_ response: DeviceRegionResponse) throws {
        try Keychain.set(JSONEncoder().encode(response), for: regionKey(response.regionCode))
    }

    static func provisioned(_ region: String) -> DeviceRegionResponse? {
        guard let data = try? Keychain.data(for: regionKey(region)) else { return nil }
        return try? JSONDecoder().decode(DeviceRegionResponse.self, from: data)
    }

    /// The complete tunnel config for a region, or nil if it was never
    /// provisioned on this device.
    static func tunnelConfig(for region: String) -> TunnelConfig? {
        guard let provisioned = provisioned(region) else { return nil }
        return TunnelConfig(privateKey: privateKey(for: region), region: provisioned)
    }

    /// Forget a region: drop both the stored response and the key. The key must
    /// go too — the server-side peer is gone, so reusing it would just be
    /// registering a stale public key.
    static func forget(_ region: String) {
        try? Keychain.remove(regionKey(region))
        try? Keychain.remove(privateKeyKey(region))
    }

    /// Wipe every region's credentials — used on sign-out.
    static func forgetAll(regions: [String]) {
        regions.forEach(forget)
    }
}
