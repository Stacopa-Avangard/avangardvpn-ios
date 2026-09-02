//
//  TunnelStore.swift — start and stop the tunnel, and track what it is doing.
//
//  The app never touches the packet tunnel directly. It writes a configuration
//  into the system's VPN preferences and asks the system to run the extension;
//  everything after that happens in another process (see
//  Tunnel/Sources/PacketTunnelProvider.swift).
//
//  So this type owns exactly one thing: the saved configuration, and the four
//  operations on it — adopt, prepare, start, stop.
//
import Foundation
import NetworkExtension

/// Live per-second transfer rates, as Android's `Throughput` carries them.
struct Throughput: Equatable {
    var downBytesPerSecond: Int64 = 0
    var upBytesPerSecond: Int64 = 0

    static let zero = Throughput()
}

@MainActor
final class TunnelStore: ObservableObject {
    @Published private(set) var status: TunnelStatus = .invalid {
        didSet {
            guard status != oldValue else { return }
            statusDidChange()
        }
    }
    @Published var errorMessage: String?

    /// Live ↓/↑ rates while the tunnel is up, zero otherwise.
    @Published private(set) var throughput: Throughput = .zero

    /// When the current session came up, for the session clock. Survives
    /// `.reasserting` — the network moved, the session did not end — and is
    /// cleared on any real teardown.
    @Published private(set) var connectedSince: Date?

    /// True across the save/permission round trip, which is the one stretch
    /// where nothing has happened yet and `status` is still the old value.
    /// Without it the UI looks inert while iOS is showing its own prompt.
    @Published private(set) var isPreparing = false

    /// The extension that runs the tunnel.
    ///
    /// ⚠️ Must match `AvangardTunnel`'s PRODUCT_BUNDLE_IDENTIFIER in
    /// project.yml. Nothing checks the two against each other at build time —
    /// a mismatch saves cleanly and then fails at `startTunnel()`, so it is
    /// pinned by a test instead.
    static let providerBundleIdentifier = "com.avangard.vpn.network-extension"

    private let store: VPNConfigurationStore
    private var configuration: VPNConfiguration?
    private var observation: Task<Void, Never>?
    private var metering: Task<Void, Never>?

    /*
      Two initialisers rather than one with a default argument.

      Under the Swift 5 language mode a default argument expression is
      evaluated in a nonisolated context, while SystemVPNConfigurationStore is
      main-actor isolated — conforming to a @MainActor protocol infers that
      isolation onto the whole type, so dropping the annotation would not help.
      Writing `init(store: VPNConfigurationStore = SystemVPNConfigurationStore())`
      fails with:

        error: call to main actor-isolated initializer 'init()' in a
               synchronous nonisolated context

      SE-0411 makes default arguments adopt the enclosing isolation, but only
      from the Swift 6 language mode. A convenience initialiser evaluates the
      expression in the initialiser's own body, which is main-actor isolated
      like the rest of the class.
    */
    convenience init() {
        self.init(store: SystemVPNConfigurationStore())
    }

    init(store: VPNConfigurationStore) {
        self.store = store
    }

    deinit {
        observation?.cancel()
        metering?.cancel()
    }

    // MARK: - Lifecycle

    /// Pick up a configuration this app saved earlier and follow it from here.
    ///
    /// Called when the connect screen appears. It matters on every launch, not
    /// just the first: the tunnel outlives the app, so an app reopened while
    /// the VPN is up must show "Connected" rather than offering to connect
    /// something that already is.
    func start() async {
        await adoptSavedConfiguration()
        observeStatusChanges()
    }

    private func adoptSavedConfiguration() async {
        do {
            configuration = mine(among: try await store.loadAll())
            status = configuration?.status ?? .invalid
        } catch {
            /*
              Deliberately silent. This runs on appear, and the user has not
              asked for anything yet — greeting them with an error about the
              VPN preference store would be noise. The failure is not lost: the
              same call runs again inside `connect`, where there is a request to
              fail and somewhere sensible to report it.
            */
            configuration = nil
            status = .invalid
        }
    }

    // MARK: - Connect

    func connect(to config: TunnelConfig, regionName: String) async {
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }

        do {
            let prepared = try await prepare(config, regionName: regionName)
            configuration = prepared
            observeStatusChanges()

            try prepared.startTunnel()

            /*
              Read the status back rather than assuming `.connecting`.
              `startVPNTunnel()` returning without throwing means the request
              was accepted, not that the tunnel is coming up — and the status
              notification for the transition may already have fired by now.
            */
            status = prepared.status
        } catch {
            errorMessage = Self.message(for: error)
            status = configuration?.status ?? .invalid
        }
    }

    /// Get a saved, enabled, up-to-date configuration back from the system.
    private func prepare(_ config: TunnelConfig, regionName: String) async throws -> VPNConfiguration {
        let existing = try await store.loadAll()

        /*
          Reuse before create. A fresh NETunnelProviderManager saved each time
          is an extra row under Settings → VPN each time — the user ends up
          with a list of identical "AvangardVPN" entries and no way to tell
          which one the app is driving.

          Everything `loadAll` returns belongs to this app, so `first` is
          already correct; preferring the one that points at our extension is
          for the case where an earlier build left something else behind.
        */
        let target = existing.first { $0.providerBundleIdentifier == Self.providerBundleIdentifier }
            ?? existing.first
            ?? store.makeNew()

        target.apply(
            VPNSettings(
                providerBundleIdentifier: Self.providerBundleIdentifier,
                providerConfiguration: config.profile.providerConfiguration,
                serverAddress: Self.host(of: config.endpoint),
                localizedDescription: "AvangardVPN — \(regionName)"
            )
        )

        try await target.save()

        /*
          ⚠️ The reload is load-bearing, and leaving it out is the classic way
          this API fails. After `saveToPreferences` the in-memory object is
          stale: the system has assigned the configuration an identifier and
          rebuilt its connection, and the copy we hold still refers to the old
          one. Starting through it fails with NEVPNError.configurationInvalid,
          or — worse — appears to succeed and brings nothing up.

          It has to be a real round trip through `loadFromPreferences`; there
          is no flag on the save that avoids it.
        */
        try await target.reload()

        return target
    }

    // MARK: - Disconnect

    /// Not async, and not throwing: `stopVPNTunnel()` is a request posted to
    /// the system, and the tunnel is not down when it returns. The status
    /// notification is what reports the outcome.
    func disconnect() {
        errorMessage = nil
        guard let configuration else { return }
        configuration.stopTunnel()
        status = configuration.status
    }

    // MARK: - Status

    private func observeStatusChanges() {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            guard let stream = self?.store.statusChanges() else { return }
            for await _ in stream {
                guard let self else { return }
                self.status = self.configuration?.status ?? .invalid
            }
        }
    }

    private func mine(among configurations: [VPNConfiguration]) -> VPNConfiguration? {
        configurations.first { $0.providerBundleIdentifier == Self.providerBundleIdentifier }
            ?? configurations.first
    }

    // MARK: - Metering

    /// Drives the session clock and the throughput ticker off one place, so
    /// every path that moves `status` — a tap here, or the user disconnecting
    /// from Settings — gets the same treatment.
    private func statusDidChange() {
        switch status {
        case .connected:
            if connectedSince == nil { connectedSince = Date() }
            startMetering()
        case .reasserting:
            // Still the same session; the rate is meaningless while it
            // re-establishes, so the meter stops but the clock keeps running.
            stopMetering()
        default:
            connectedSince = nil
            stopMetering()
        }
    }

    /// Polls the extension once a second and reports the delta.
    ///
    /// The first reading only seeds the baseline — emitting on it would
    /// report the whole session's traffic as one second of it, which is the
    /// spike Android's ticker documents avoiding. A counter that goes
    /// backwards (the backend restarted under a reconnect) clamps to zero
    /// rather than reporting a negative rate.
    private func startMetering() {
        guard metering == nil else { return }
        metering = Task { [weak self] in
            var previous: (rx: Int64, tx: Int64)?

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }

                guard
                    self.status == .connected,
                    let report = await self.configuration?.runtimeConfiguration(),
                    let counters = Self.counters(in: report)
                else {
                    // Lost the channel: drop the baseline so the next good
                    // reading seeds a fresh one instead of differencing
                    // against a stale counter across the gap.
                    previous = nil
                    self.throughput = .zero
                    continue
                }

                if let previous {
                    self.throughput = Throughput(
                        downBytesPerSecond: max(0, counters.rx - previous.rx),
                        upBytesPerSecond: max(0, counters.tx - previous.tx)
                    )
                }
                previous = counters
            }
        }
    }

    private func stopMetering() {
        metering?.cancel()
        metering = nil
        throughput = .zero
    }

    /// Sum the transfer counters out of wireguard-go's UAPI report.
    ///
    /// The format is one `key=value` per line, with the peer's counters
    /// following its `public_key`. Summed across peers rather than taken from
    /// the first: there is exactly one peer today, and a sum stays correct if
    /// that ever stops being true.
    ///
    /// `rx_bytes` is what came back from the peer — the user's download.
    static func counters(in uapi: String) -> (rx: Int64, tx: Int64)? {
        var rx: Int64 = 0
        var tx: Int64 = 0
        var sawCounter = false

        for line in uapi.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Int64(parts[1]) else { continue }
            switch parts[0] {
            case "rx_bytes":
                rx += value
                sawCounter = true
            case "tx_bytes":
                tx += value
                sawCounter = true
            default:
                break
            }
        }

        return sawCounter ? (rx, tx) : nil
    }

    // MARK: - Presentation

    /// The host half of `host:port`.
    ///
    /// Cosmetic — `serverAddress` is only what iOS shows under Settings → VPN —
    /// but a value with the port glued on reads like a mistake, and a bracketed
    /// IPv6 literal reads like a broken one.
    static func host(of endpoint: String) -> String {
        // [2001:db8::1]:51820
        if endpoint.hasPrefix("["), let close = endpoint.firstIndex(of: "]") {
            return String(endpoint[endpoint.index(after: endpoint.startIndex)..<close])
        }
        /*
          vpn.example.com:51820 → vpn.example.com, but a bare IPv6 literal is
          all colons and carries no port, so split only when there is exactly
          one — otherwise `2001:db8::1` would be truncated to `2001`.
        */
        let parts = endpoint.split(separator: ":")
        if parts.count == 2 {
            return String(parts[0])
        }
        return endpoint
    }

    /// NEVPNError is not localised and its raw description is a domain and a
    /// code, so each case the user can actually act on gets its own sentence.
    static func message(for error: Error) -> String {
        let fallback = "Could not start the tunnel. Please try again."

        guard let vpnError = error as? NEVPNError else {
            return (error as? LocalizedError)?.errorDescription ?? fallback
        }

        switch vpnError.code {
        case .configurationReadWriteFailed:
            /*
              What comes back when the user answers "Don't Allow" to the system
              prompt on the first save. It is also the generic preference-store
              write failure, hence the hedge — claiming outright that they
              declined would be wrong for anyone who hit the other case.
            */
            return "iOS would not save the VPN configuration. If you dismissed the permission prompt, tap Connect again and allow it."
        case .configurationInvalid:
            return "iOS rejected the VPN configuration. Please reinstall the app."
        case .configurationDisabled:
            return "This VPN configuration is switched off in Settings → VPN."
        case .configurationStale:
            return "The VPN configuration changed while connecting. Please try again."
        case .connectionFailed:
            return "The tunnel could not be started. Check your connection and try again."
        default:
            return fallback
        }
    }
}

