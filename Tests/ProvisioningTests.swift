//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  ProvisioningTests.swift — on-device keygen + region registration.
//
//  Same harness as AuthFlowTests: the network tests need a local backend and a
//  pre-verified login session (see Scripts/run-auth-tests.sh). The pure ones —
//  key generation and config assembly — run anywhere.
//
import CryptoKit
import XCTest
@testable import AvangardVPN

final class ProvisioningTests: XCTestCase {

    /// Whether a backend was supplied to test against. Empty counts as absent
    /// (see `AppConfig.apiBaseOverride`), and production is refused outright —
    /// these tests register devices and would otherwise do so on the live server.
    private var isConfigured: Bool {
        guard let base = AppConfig.apiBaseOverride else { return false }
        return base != AppConfig.productionBaseURL.absoluteString
    }

    // MARK: - Keys (no backend needed)

    /// The backend validates uploaded keys with `^[A-Za-z0-9+/]{43}=$`. If our
    /// encoding drifts from that, registration fails with a 400 that says only
    /// "invalid_body", so pin it here.
    func testGeneratedPublicKeyMatchesBackendFormat() {
        let pair = WireGuardKeyPair.generate()
        let pattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9+/]{43}=$")

        for key in [pair.publicKey, pair.privateKey] {
            let range = NSRange(key.startIndex..., in: key)
            XCTAssertNotNil(
                pattern.firstMatch(in: key, range: range),
                "key not in the format the backend accepts: \(key)"
            )
            XCTAssertEqual(Data(base64Encoded: key)?.count, 32, "WireGuard keys are 32 bytes")
        }
    }

    func testPublicKeyIsDerivableFromPrivateKey() {
        let pair = WireGuardKeyPair.generate()
        XCTAssertEqual(WireGuardKeyPair.publicKey(forPrivateKey: pair.privateKey), pair.publicKey)
    }

    func testEachGeneratedKeyPairIsDistinct() {
        // Regions must not share a keypair — `peers.public_key` is UNIQUE
        // server-side and a reused key is rejected with 409.
        let keys = (0..<16).map { _ in WireGuardKeyPair.generate().publicKey }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    // MARK: - Config assembly (no backend needed)

    private func response(assignedIpv6: String?) -> DeviceRegionResponse {
        DeviceRegionResponse(
            regionCode: "sg",
            displayName: "Singapore",
            serverPublicKey: "c2VydmVycHVibGlja2V5MDAwMDAwMDAwMDAwMDAwMDA=",
            endpoint: "vpn.example.com:51820",
            allowedIps: "0.0.0.0/0, ::/0",
            dns: "1.1.1.1, 1.0.0.1",
            assignedIp: "10.7.0.5",
            assignedIpv6: assignedIpv6,
            presharedKey: "cHNrMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA="
        )
    }

    /// The rule from the Android rollout: route `::/0` only when the server
    /// actually assigned a v6 address. Otherwise v6 traffic enters a tunnel it
    /// can never be sourced from and black-holes.
    func testIPv4OnlyRegionStripsIPv6Routes() {
        let config = TunnelConfig(privateKey: "priv", region: response(assignedIpv6: nil))

        XCTAssertEqual(config.addresses, ["10.7.0.5/32"])
        XCTAssertEqual(config.allowedIps, ["0.0.0.0/0"])
    }

    func testDualStackRegionKeepsIPv6Routes() {
        let config = TunnelConfig(privateKey: "priv", region: response(assignedIpv6: "fd42:8::5"))

        XCTAssertEqual(config.addresses, ["10.7.0.5/32", "fd42:8::5/128"])
        XCTAssertEqual(config.allowedIps, ["0.0.0.0/0", "::/0"])
    }

    // MARK: - Registration against a real backend

    /// End-to-end: sign in, list regions, register this device on one, and
    /// assemble a config from the reply. Also pins idempotency — registering
    /// the same region twice must return the same assigned IP, not burn a
    /// second address out of the pool.
    func testProvisionRegionAndAssembleConfig() async throws {
        try XCTSkipUnless(isConfigured, "set AVANGARD_API_BASE to run integration tests")
        try await signIn(using: "AVANGARD_VERIFIED_SESSION_ID_3")

        let regions = try await APIClient.shared.regions()
        XCTAssertFalse(regions.isEmpty, "backend should have at least the seeded region")
        let region = try XCTUnwrap(regions.first)

        let provisioned = try await APIClient.shared.provision(regionCode: region.regionCode)
        XCTAssertEqual(provisioned.regionCode, region.regionCode)
        XCTAssertFalse(provisioned.serverPublicKey.isEmpty)
        XCTAssertFalse(provisioned.presharedKey.isEmpty)
        XCTAssertTrue(provisioned.endpoint.contains(":"), "endpoint should carry its port")

        try PeerStore.save(provisioned)
        let config = try XCTUnwrap(PeerStore.tunnelConfig(for: region.regionCode))
        XCTAssertTrue(config.addresses.contains("\(provisioned.assignedIp)/32"))
        XCTAssertEqual(config.serverPublicKey, provisioned.serverPublicKey)

        // The uploaded public key must match the private key we kept.
        let expectedPublic = WireGuardKeyPair.publicKey(forPrivateKey: config.privateKey)
        XCTAssertEqual(expectedPublic, PeerStore.publicKey(for: region.regionCode))

        // Idempotent: same device + region → same peer.
        let again = try await APIClient.shared.provision(regionCode: region.regionCode)
        XCTAssertEqual(again.assignedIp, provisioned.assignedIp)

        // And the device now shows up in the account's device list.
        let devices = try await APIClient.shared.devices()
        XCTAssertTrue(
            devices.contains { $0.deviceId == DeviceIdentity.id },
            "provisioned device should appear in /api/me/devices"
        )
    }

    /// Claim a pre-verified login session so the following calls are authorised.
    private func signIn(using variable: String) async throws {
        guard let sessionId = AppConfig.environment(variable) else {
            throw XCTSkip("no pre-verified session supplied; run via Scripts/run-auth-tests.sh")
        }
        let claim = try await APIClient.shared.poll(loginSessionId: sessionId)
        try XCTSkipUnless(claim.status == .verified, "session was not in the verified state")
        try TokenStore.save(SessionResponse(
            access: try XCTUnwrap(claim.access),
            refresh: try XCTUnwrap(claim.refresh),
            user: try XCTUnwrap(claim.user)
        ))
    }
}
