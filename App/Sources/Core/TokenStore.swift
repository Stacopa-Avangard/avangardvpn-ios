//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  TokenStore.swift — persistence for the signed-in session.
//
//  Refresh-token rotation has no grace window server-side: the moment
//  `/auth/refresh` mints a new pair, the token you sent is dead. So the new
//  refresh must reach the Keychain BEFORE the new access is used for anything.
//  `save(_:)` is the only writer, and it writes refresh first for that reason —
//  if the process dies mid-save the worst case is a stale access token, which
//  simply triggers another refresh. The reverse order would lose the session.
//
import Foundation

enum TokenStore {
    private enum Key {
        static let access = "auth.access"
        static let refresh = "auth.refresh"
        static let user = "auth.user"
    }

    static var access: String? {
        try? Keychain.string(for: Key.access)
    }

    static var refresh: String? {
        try? Keychain.string(for: Key.refresh)
    }

    static var user: AuthUser? {
        guard let data = try? Keychain.data(for: Key.user) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    /// True when there is a refresh token to work with. The access token may
    /// well be expired — that is recoverable, a missing refresh is not.
    static var hasSession: Bool { refresh != nil }

    static func save(_ session: SessionResponse) throws {
        // Order matters — see the file comment.
        try Keychain.set(session.refresh, for: Key.refresh)
        try Keychain.set(session.access, for: Key.access)
        try Keychain.set(JSONEncoder().encode(session.user), for: Key.user)
    }

    /// Wipe the session. Best-effort: a failure to delete one item must not
    /// leave the app stuck in a half-signed-in state, so errors are ignored.
    static func clear() {
        try? Keychain.remove(Key.access)
        try? Keychain.remove(Key.refresh)
        try? Keychain.remove(Key.user)
    }
}
