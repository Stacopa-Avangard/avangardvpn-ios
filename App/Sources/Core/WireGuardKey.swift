//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  WireGuardKey.swift — on-device keypair generation.
//
//  The central rule of this project: the server never holds a private key for
//  anyone. Keys are generated here, the private half stays in the Keychain, and
//  only the public half is ever uploaded. There is deliberately no code path
//  that sends a private key anywhere.
//
//  WireGuard keys are X25519, which is exactly what CryptoKit's
//  `Curve25519.KeyAgreement` produces — the raw 32-byte representations are
//  interchangeable with what `wg genkey` / `wg pubkey` emit.
//
import CryptoKit
import Foundation

struct WireGuardKeyPair {
    /// Base64, 44 chars including the `=` — the form the backend validates
    /// with `^[A-Za-z0-9+/]{43}=$` and the form `wg` writes in a `.conf`.
    let privateKey: String
    let publicKey: String

    static func generate() -> WireGuardKeyPair {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return WireGuardKeyPair(
            privateKey: key.rawRepresentation.base64EncodedString(),
            publicKey: key.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    /// Recover the public half from a stored private key, so a device that
    /// already has a key can re-register the same peer without minting a new
    /// one (re-registration is idempotent server-side per device+region).
    static func publicKey(forPrivateKey privateKey: String) -> String? {
        guard let data = Data(base64Encoded: privateKey),
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        else { return nil }
        return key.publicKey.rawRepresentation.base64EncodedString()
    }
}
