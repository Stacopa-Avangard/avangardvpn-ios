//
//  VPNConfiguration.swift — the app's side of the system VPN configuration.
//
//  This is the seam over NETunnelProviderManager: one saved entry under
//  Settings → VPN, plus the store that lists and creates them.
//
//  ⚠️ The protocol is not decoration, and it is not dependency injection as a
//  habit. NETunnelProviderManager cannot be exercised by any test we can run:
//
//    - it needs the packet-tunnel-provider entitlement, which is paid-only, so
//      the free-team device build cannot carry it;
//    - the unit tests are hosted in AvangardVPNDeviceTest on a Simulator (see
//      project.yml for why they cannot be hosted in the app), and the VPN
//      preference store there is not something a test may write to;
//    - and every call is a completion-handler round trip into a system daemon.
//
//  Without a seam the connect sequence would be verifiable only by installing
//  on a phone, which is blocked on the Apple Developer Program enrolment. With
//  it, the ordering and reuse rules are pinned by tests that run on every push.
//  The protocol is deliberately shaped like the API it wraps rather than like
//  something more convenient, so the fake cannot be more forgiving than the
//  real thing.
//
import NetworkExtension

/// Everything the app sets on a configuration, applied in one go.
///
/// One method rather than individual setters because
/// `NEVPNManager.protocolConfiguration` is replaced wholesale in the working
/// pattern: build a fresh `NETunnelProviderProtocol` and assign it. Mutating
/// the object read back out of that property is the shape that produces saves
/// which report success and change nothing.
struct VPNSettings {
    /// Must equal the extension target's PRODUCT_BUNDLE_IDENTIFIER. A typo here
    /// does not fail the save — it fails much later, when the system looks for
    /// an extension by that name and cannot start the tunnel.
    let providerBundleIdentifier: String

    /// `TunnelProfile.providerConfiguration`. Crosses the process boundary and
    /// is persisted by the system inside the saved VPN configuration.
    let providerConfiguration: [String: Any]

    /// Cosmetic: what iOS prints as the server under Settings → VPN.
    let serverAddress: String

    /// The row's name under Settings → VPN.
    let localizedDescription: String
}

@MainActor
protocol VPNConfiguration: AnyObject {
    /// Read to tell our configuration apart from any other this app has saved.
    /// The rest of what `apply` writes is never read back — the app is the
    /// authority on it, not the preference store.
    var providerBundleIdentifier: String? { get }

    var status: TunnelStatus { get }

    func apply(_ settings: VPNSettings)

    /// Write to the system preference store. On first use this is what raises
    /// the "…Would Like to Add VPN Configurations" prompt, so it is also the
    /// call that fails when the user declines.
    func save() async throws

    /// Read back after saving. See `TunnelStore.prepare` — not optional.
    func reload() async throws

    func startTunnel() throws
    func stopTunnel()

    /// The tunnel's own runtime counters, as the extension reports them — the
    /// same text `wg show` would print. This is the ONLY channel the app has
    /// into the running extension (`handleAppMessage` on the other side).
    ///
    /// Nil whenever there is nothing to ask: the tunnel is not up, the
    /// connection is not a provider session, or the message was refused.
    func runtimeConfiguration() async -> String?
}

extension VPNConfiguration {
    /// Defaulted so the test fakes, which have no provider session and cannot
    /// have one, keep conforming without having to pretend to answer.
    func runtimeConfiguration() async -> String? { nil }
}

@MainActor
protocol VPNConfigurationStore {
    /// Every VPN configuration this app has saved. The system scopes the list
    /// to the calling app, so anything returned here is ours.
    func loadAll() async throws -> [VPNConfiguration]

    func makeNew() -> VPNConfiguration

    /// Fires whenever any of this app's tunnels changes state — including
    /// changes the app did not cause, such as the user disconnecting from
    /// Settings or the system tearing the tunnel down.
    func statusChanges() -> AsyncStream<Void>
}

// MARK: - The real thing

@MainActor
final class SystemVPNConfiguration: VPNConfiguration {
    private let manager: NETunnelProviderManager

    init(_ manager: NETunnelProviderManager) {
        self.manager = manager
    }

    var providerBundleIdentifier: String? {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
    }

    var status: TunnelStatus { TunnelStatus(manager.connection.status) }

    func apply(_ settings: VPNSettings) {
        let configured = NETunnelProviderProtocol()
        configured.providerBundleIdentifier = settings.providerBundleIdentifier
        configured.providerConfiguration = settings.providerConfiguration
        configured.serverAddress = settings.serverAddress

        manager.protocolConfiguration = configured
        manager.localizedDescription = settings.localizedDescription

        /*
          Always re-enabled on save. A configuration the user switched off in
          Settings → VPN stays off, and `startVPNTunnel()` then fails with
          NEVPNError.configurationDisabled — an error that reads like a bug in
          the app rather than like a switch the user flipped. Tapping Connect
          is a clear enough request to turn it back on.
        */
        manager.isEnabled = true

        /*
          On-demand stays off, deliberately. It would have iOS raise the tunnel
          on its own whenever the rules match, which is a product decision on a
          metered plan rather than a technical default — and it would also
          reconnect after the user had deliberately disconnected.
        */
        manager.isOnDemandEnabled = false
    }

    func save() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func reload() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func startTunnel() throws {
        try manager.connection.startVPNTunnel()
    }

    func stopTunnel() {
        manager.connection.stopVPNTunnel()
    }

    func runtimeConfiguration() async -> String? {
        /*
          `sendProviderMessage` throws rather than returning an error when the
          session is not running, and the tunnel goes down at moments the app
          does not choose — so a poll landing on a torn-down tunnel is normal
          traffic, not a fault. Every failure here is a nil, never a throw:
          the caller's only sensible response is to show no rate, which is
          what a nil already means.
        */
        guard let session = manager.connection as? NETunnelProviderSession else { return nil }

        return await withCheckedContinuation { continuation in
            do {
                // The extension ignores the body and always answers with the
                // runtime configuration; an empty message keeps it that way.
                try session.sendProviderMessage(Data()) { response in
                    continuation.resume(returning: response.flatMap { String(data: $0, encoding: .utf8) })
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

@MainActor
struct SystemVPNConfigurationStore: VPNConfigurationStore {
    func loadAll() async throws -> [VPNConfiguration] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[VPNConfiguration], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                // The callback arrives on a queue of the system's choosing and
                // SystemVPNConfiguration is main-actor isolated, so the wrap
                // has to happen back on the main actor.
                Task { @MainActor in
                    continuation.resume(returning: (managers ?? []).map(SystemVPNConfiguration.init))
                }
            }
        }
    }

    func makeNew() -> VPNConfiguration {
        SystemVPNConfiguration(NETunnelProviderManager())
    }

    func statusChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            /*
              Observed with `object: nil` rather than against one connection.
              The app owns a single configuration, and the connection object is
              replaced whenever the manager is reloaded — an observer bound to a
              particular one goes quiet after the first save without raising
              anything. An app-wide notification cannot go stale, and this app
              has nothing else generating them.
            */
            let token = NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange,
                object: nil,
                queue: .main
            ) { _ in
                continuation.yield(())
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
}
