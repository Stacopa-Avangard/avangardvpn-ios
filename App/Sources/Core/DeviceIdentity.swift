//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  DeviceIdentity.swift — the stable id this device registers under.
//
//  Deliberately NOT `identifierForVendor`: that resets when the user deletes
//  every app from this vendor, and the backend enforces a per-user device cap
//  (`DEVICE_CAP`). A rotating id would burn through that cap — each reinstall
//  would look like a brand-new device and the user would eventually be locked
//  out of registering at all.
//
//  A UUID minted once and kept in the Keychain survives app deletion on iOS, so
//  a reinstall re-registers as the SAME device and the existing peers are
//  reused (registration is idempotent per user+device+region).
//
import Foundation
import UIKit

enum DeviceIdentity {
    private static let key = "device.id"

    /// Stable per-install-lineage id. Generated on first use.
    static var id: String {
        if let existing = try? Keychain.string(for: key) {
            return existing
        }
        let fresh = UUID().uuidString
        try? Keychain.set(fresh, for: key)
        return fresh
    }

    /// Human label shown on the Account screen and in the admin portal.
    ///
    /// iOS 16 stopped handing out the user-assigned device name without a
    /// special entitlement — `UIDevice.name` now returns the model ("iPhone").
    /// That is fine as a label, but it means several of a user's devices can
    /// share a name; `deviceId` is what actually distinguishes them.
    static var name: String {
        let name = UIDevice.current.name
        return String(name.prefix(64)) // backend caps deviceName at 64 chars
    }
}
