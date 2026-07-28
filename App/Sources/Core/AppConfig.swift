//
//  AppConfig.swift — compile-time constants shared across the app.
//
//  The backend is the same one the Android app talks to
//  (fixidn/wireguard-dashboard). No per-build configuration: there is exactly
//  one production deployment, so the base URL is a constant rather than a
//  scheme/xcconfig knob.
//
import Foundation

enum AppConfig {
    static let productionBaseURL = URL(string: "https://vpn.stacopa-avangard.com")!

    /// Backend origin. Serves both `/auth/*` and `/api/*`.
    ///
    /// In DEBUG builds only, `AVANGARD_API_BASE` redirects the app at a local
    /// backend (`pnpm dev`) so the auth and provisioning flows can be exercised
    /// without touching production or emailing anyone. Deliberately compiled
    /// out of Release — a shipped build must not be redirectable by an
    /// environment variable.
    static let baseURL: URL = {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["AVANGARD_API_BASE"],
           let url = URL(string: override) {
            return url
        }
        #endif
        return productionBaseURL
    }()

    /// Shared container between the app and the tunnel extension. The extension
    /// reads the tunnel config the app writes here (wired in P2/P3).
    static let appGroup = "group.com.avangard.vpn"

    /// Keychain service for this app's secrets (tokens now; the device private
    /// key in P2). Namespaced so it never collides with another app's items.
    static let keychainService = "com.avangard.vpn"

    /// How often the app asks `/auth/poll` whether the emailed link was clicked.
    /// The backend sizes its rate limit around ~3s (120 req/min per IP), so do
    /// not shorten this without checking `middleware/rate-limit.ts` first.
    static let pollInterval: Duration = .seconds(3)

    /// Give up polling after this long. Matches the backend's magic-link TTL
    /// (`MAGIC_LINK_TTL_MIN`, 15 min) — past it the token cannot be redeemed.
    static let pollTimeout: Duration = .seconds(15 * 60)
}
