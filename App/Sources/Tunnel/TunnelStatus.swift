//
//  TunnelStatus.swift — the tunnel's state, in the terms the UI needs.
//
//  A narrowing of NEVPNStatus. It exists for two reasons: the app should not
//  have to import NetworkExtension to render a label, and NEVPNStatus is an
//  ObjC enum that can gain cases, so the translation belongs in exactly one
//  place rather than at every switch site.
//
import NetworkExtension

enum TunnelStatus: Equatable {
    /// No configuration has been saved yet, or the system could not read one.
    /// Distinct from `.disconnected` so the store can tell "never set up" from
    /// "set up and idle" — the user sees the same thing either way.
    case invalid
    case disconnected
    case connecting
    case connected
    /// Still up, but re-establishing after the network moved underneath it —
    /// Wi-Fi to cellular, for instance. Shown as its own state because
    /// reporting it as "Connected" hides a real interruption, and reporting it
    /// as "Connecting" suggests the user has to wait to be protected again.
    case reasserting
    case disconnecting

    init(_ status: NEVPNStatus) {
        switch status {
        case .invalid: self = .invalid
        case .disconnected: self = .disconnected
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .reasserting: self = .reasserting
        case .disconnecting: self = .disconnecting
        // NEVPNStatus is NS_ENUM: new cases are a source-compatible change on
        // Apple's side. Treating an unknown one as `.invalid` keeps the UI
        // honest — it says "not connected" rather than claiming protection we
        // cannot vouch for.
        @unknown default: self = .invalid
        }
    }

    /// Mid-flight. The connect control shows a spinner rather than a verb.
    var isTransitioning: Bool {
        self == .connecting || self == .disconnecting || self == .reasserting
    }

    /// Whether tapping the control should tear the tunnel down. `.connecting`
    /// counts: a connect attempt that is taking too long is exactly when a user
    /// wants out, and NEVPNConnection accepts a stop in that state.
    var offersDisconnect: Bool {
        self == .connected || self == .connecting || self == .reasserting
    }

    var title: String {
        switch self {
        // "Not configured" would be accurate and useless — the user did not
        // fail to do anything, the app simply has not saved a profile yet.
        case .invalid, .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reasserting: return "Reconnecting…"
        case .disconnecting: return "Disconnecting…"
        }
    }
}
