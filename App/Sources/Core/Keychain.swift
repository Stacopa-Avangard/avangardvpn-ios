//
//  Keychain.swift — the only place secrets are persisted.
//
//  Mirrors what the Android app does with EncryptedSharedPreferences: session
//  tokens (and, from P2, the device's WireGuard private key) never touch
//  UserDefaults or a file. Items are stored `AfterFirstUnlockThisDeviceOnly`:
//
//  - *AfterFirstUnlock* so the tunnel extension can still read the config when
//    the screen is locked — an always-on VPN has to reconnect without the user
//    unlocking the phone.
//  - *ThisDeviceOnly* so nothing syncs to iCloud Keychain or restores onto a
//    different device. A peer's credentials are bound to the device that
//    generated them; the server would hand a restored copy a different peer.
//
import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case dataCorrupted
}

enum Keychain {
    /// Store (or replace) a value. Writing is upsert: delete-then-add keeps the
    /// accessibility attribute authoritative even if an older item used another.
    static func set(_ value: Data, for key: String, accessGroup: String? = nil) throws {
        var query = baseQuery(for: key, accessGroup: accessGroup)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func set(_ value: String, for key: String, accessGroup: String? = nil) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataCorrupted }
        try set(data, for: key, accessGroup: accessGroup)
    }

    /// Read a value. A missing item is `nil`, not an error — callers routinely
    /// ask for tokens that were never written (first launch, after sign-out).
    static func data(for key: String, accessGroup: String? = nil) throws -> Data? {
        var query = baseQuery(for: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return item as? Data
    }

    static func string(for key: String, accessGroup: String? = nil) throws -> String? {
        guard let data = try data(for: key, accessGroup: accessGroup) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataCorrupted
        }
        return string
    }

    /// Remove a value. Deleting something absent is a no-op, not an error.
    static func remove(_ key: String, accessGroup: String? = nil) throws {
        let status = SecItemDelete(baseQuery(for: key, accessGroup: accessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(for key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
