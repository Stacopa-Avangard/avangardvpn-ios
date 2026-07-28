//
//  Models.swift — wire types for the backend API.
//
//  These mirror `backend/src/routes/auth.ts` exactly. The backend speaks
//  camelCase already, so no key-decoding strategy is applied — a mismatch here
//  should fail loudly rather than be papered over by a converter.
//
import Foundation

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String
    let name: String
    let role: String

    var isAdmin: Bool { role == "admin" }
}

/// `/auth/verify` and `/auth/refresh` both return this shape.
struct SessionResponse: Codable {
    let access: String
    let refresh: String
    let user: AuthUser
}

/// `/auth/poll` — a single endpoint with three outcomes.
///
/// `expired` deliberately covers "unknown id", "past its TTL", and "already
/// claimed": the backend refuses to distinguish them so a caller cannot probe
/// for valid login-session ids.
struct PollResponse: Codable {
    enum Status: String, Codable {
        case pending
        case verified
        case expired
    }

    let status: Status
    // Present only when status == .verified — tokens are minted at claim time.
    let access: String?
    let refresh: String?
    let user: AuthUser?
}

// MARK: - Provisioning

/// One entry of `GET /api/me/regions` — the picker catalogue. Carries no
/// secrets and creates no peer; choosing one is what provisions it.
struct Region: Codable, Equatable, Identifiable {
    let regionCode: String
    let displayName: String
    let sortOrder: Int

    var id: String { regionCode }
}

struct RegionCatalog: Codable {
    let regions: [Region]
}

/// Body of `POST /api/me/devices/regions`. Note what is absent: the private
/// key. Only the public half is ever uploaded.
struct DeviceRegionRequest: Encodable {
    let deviceId: String
    let deviceName: String
    let regionCode: String
    let publicKey: String
}

/// Response of `POST /api/me/devices/regions` — the server-side half of the
/// tunnel config. The app pairs this with its own private key to build a
/// complete `.conf` locally; the server never assembles one.
struct DeviceRegionResponse: Codable, Equatable {
    let regionCode: String
    let displayName: String
    let serverPublicKey: String
    /// Already includes the port, e.g. `vpn.example.com:51820`.
    let endpoint: String
    let allowedIps: String
    let dns: String
    let assignedIp: String
    /// Non-nil only when the region is IPv6-enabled. Its absence is meaningful:
    /// the tunnel must NOT route `::/0` without it, or v6 traffic black-holes.
    let assignedIpv6: String?
    let presharedKey: String
}

/// One device from `GET /api/me/devices`, grouped across its regions.
struct DeviceSummary: Codable, Equatable, Identifiable {
    let deviceId: String
    let deviceName: String
    let createdAt: Int?
    let lastHandshakeAt: Int?
    let regions: [String]

    var id: String { deviceId }
}

struct DeviceList: Codable {
    let devices: [DeviceSummary]
}

/// `GET /api/me/usage` — bandwidth against the monthly quota.
struct UsageSummary: Codable, Equatable {
    /// Period key the backend is accumulating into, e.g. `2026-07`.
    let period: String
    let usedBytes: Int64
    let quotaBytes: Int64
    /// True when the account has no monthly cap (`quotaBytes <= 0`).
    let unlimited: Bool
    /// True once the backend removed the peers for going over quota.
    let suspended: Bool

    /// Share of the quota consumed. Zero when unlimited — there is no
    /// denominator to divide by, and a meter would be meaningless.
    var fraction: Double {
        guard !unlimited, quotaBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(quotaBytes)
    }
}
