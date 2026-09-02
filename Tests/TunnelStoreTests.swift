//
//  TunnelStoreTests.swift — the app half of the tunnel: saving the system VPN
//  configuration and starting the extension through it.
//
//  These run against a fake VPN preference store, and that is not a shortcut.
//  NETunnelProviderManager needs the paid-only packet-tunnel-provider
//  entitlement and writes to a system preference store, so it cannot be driven
//  from a Simulator test host — see the header of VPNConfiguration.swift.
//
//  What is worth pinning here is sequencing and identity, because both fail
//  quietly on a device: a missing reload starts nothing while reporting
//  success, a wrong bundle identifier saves cleanly and fails later, and a
//  configuration created instead of reused leaves the user with duplicate rows
//  in Settings that nobody notices until there are four of them.
//
import NetworkExtension
import XCTest
@testable import AvangardVPN

// MARK: - Fakes

/// One shared, ordered log across the store and every configuration, so tests
/// can assert what happened *in what order* rather than only that it happened.
@MainActor
final class VPNRecorder {
    var calls: [String] = []
}

@MainActor
final class FakeVPNConfiguration: VPNConfiguration {
    private let recorder: VPNRecorder
    private let label: String
    private let preexistingBundleIdentifier: String?

    /// What `TunnelStore` asked to be written. The real observation point:
    /// everything the app decides ends up here.
    private(set) var applied: VPNSettings?

    var statusValue: TunnelStatus = .disconnected
    var saveError: Error?
    var reloadError: Error?
    var startError: Error?

    init(recorder: VPNRecorder, label: String, providerBundleIdentifier: String? = nil) {
        self.recorder = recorder
        self.label = label
        self.preexistingBundleIdentifier = providerBundleIdentifier
    }

    var providerBundleIdentifier: String? {
        applied?.providerBundleIdentifier ?? preexistingBundleIdentifier
    }

    var status: TunnelStatus { statusValue }

    func apply(_ settings: VPNSettings) {
        recorder.calls.append("\(label).apply")
        applied = settings
    }

    func save() async throws {
        recorder.calls.append("\(label).save")
        if let saveError { throw saveError }
    }

    func reload() async throws {
        recorder.calls.append("\(label).reload")
        if let reloadError { throw reloadError }
    }

    func startTunnel() throws {
        recorder.calls.append("\(label).start")
        if let startError { throw startError }
        statusValue = .connecting
    }

    func stopTunnel() {
        recorder.calls.append("\(label).stop")
        statusValue = .disconnecting
    }
}

@MainActor
final class FakeVPNConfigurationStore: VPNConfigurationStore {
    private let recorder: VPNRecorder

    var existing: [FakeVPNConfiguration] = []
    var loadError: Error?
    private(set) var createdCount = 0
    private(set) var created: FakeVPNConfiguration?

    private var continuation: AsyncStream<Void>.Continuation?

    init(recorder: VPNRecorder) {
        self.recorder = recorder
    }

    func loadAll() async throws -> [VPNConfiguration] {
        recorder.calls.append("loadAll")
        if let loadError { throw loadError }
        return existing
    }

    func makeNew() -> VPNConfiguration {
        recorder.calls.append("makeNew")
        createdCount += 1
        let configuration = FakeVPNConfiguration(recorder: recorder, label: "new")
        created = configuration
        existing.append(configuration)
        return configuration
    }

    func statusChanges() -> AsyncStream<Void> {
        // AsyncStream runs its builder synchronously, so the continuation is
        // set by the time this returns. `makeStream()` would be tidier but is
        // iOS 17 and the deployment target is 16.
        var captured: AsyncStream<Void>.Continuation!
        let stream = AsyncStream<Void> { captured = $0 }
        continuation = captured
        return stream
    }

    func emitStatusChange() {
        continuation?.yield(())
    }
}

// MARK: - Tests

@MainActor
final class TunnelStoreTests: XCTestCase {

    /*
      Built inline rather than in `setUp`. XCTest instantiates the test class
      once per test method, so these are already fresh for each one — and
      overriding a nonisolated XCTestCase method from a @MainActor subclass is
      an actor-isolation mismatch that is a warning today and an error under
      the Swift 6 language mode.
    */
    private let recorder = VPNRecorder()
    private lazy var vpn = FakeVPNConfigurationStore(recorder: recorder)
    private lazy var tunnel = TunnelStore(store: vpn)

    // MARK: - Fixtures

    private func region(code: String = "sg", assignedIpv6: String? = nil) -> DeviceRegionResponse {
        DeviceRegionResponse(
            regionCode: code,
            displayName: "Singapore",
            serverPublicKey: "c2VydmVycHVibGlja2V5MDAwMDAwMDAwMDAwMDAwMDA=",
            endpoint: "sg.example.com:51820",
            allowedIps: "0.0.0.0/0, ::/0",
            dns: "1.1.1.1, 1.0.0.1",
            assignedIp: "10.7.0.5",
            assignedIpv6: assignedIpv6,
            presharedKey: "cHNrMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA="
        )
    }

    private func config() -> TunnelConfig {
        TunnelConfig(
            privateKey: "cHJpdmF0ZWtleTAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=",
            region: region()
        )
    }

    private func connect() async {
        await tunnel.connect(to: config(), regionName: "Singapore")
    }

    // MARK: - The connect sequence

    /// The one that matters most. `saveToPreferences` leaves the in-memory
    /// object stale — starting through it without a `loadFromPreferences`
    /// round trip brings nothing up while reporting success. Order, not just
    /// presence.
    func testConnectAppliesSavesReloadsThenStarts() async {
        await connect()

        XCTAssertEqual(
            recorder.calls,
            ["loadAll", "makeNew", "new.apply", "new.save", "new.reload", "new.start"]
        )
    }

    func testConnectCreatesAConfigurationWhenTheDeviceHasNone() async {
        await connect()
        XCTAssertEqual(vpn.createdCount, 1)
    }

    /// A new manager saved on every connect is a new row under Settings → VPN
    /// on every connect.
    func testConnectReusesAnExistingConfigurationRatherThanAddingOne() async {
        let existing = FakeVPNConfiguration(
            recorder: recorder,
            label: "existing",
            providerBundleIdentifier: TunnelStore.providerBundleIdentifier
        )
        vpn.existing = [existing]

        await connect()

        XCTAssertEqual(vpn.createdCount, 0, "should have reused the saved configuration")
        XCTAssertNotNil(existing.applied)
        XCTAssertFalse(recorder.calls.contains("makeNew"))
    }

    /// If an older build left something else behind, take the one that points
    /// at our extension rather than whichever happens to be first.
    func testConnectPrefersTheConfigurationPointingAtOurExtension() async {
        let stray = FakeVPNConfiguration(
            recorder: recorder,
            label: "stray",
            providerBundleIdentifier: "com.example.something.else"
        )
        let ours = FakeVPNConfiguration(
            recorder: recorder,
            label: "ours",
            providerBundleIdentifier: TunnelStore.providerBundleIdentifier
        )
        vpn.existing = [stray, ours]

        await connect()

        XCTAssertNotNil(ours.applied)
        XCTAssertNil(stray.applied, "the stray configuration should have been left alone")
    }

    // MARK: - What gets written

    /// Pinned as a literal on purpose. This has to equal AvangardTunnel's
    /// PRODUCT_BUNDLE_IDENTIFIER in project.yml, nothing checks that at build
    /// time, and getting it wrong saves cleanly and then fails to start with an
    /// error that points nowhere near the cause.
    func testAppliedSettingsNameTheTunnelExtension() async {
        await connect()

        XCTAssertEqual(
            vpn.created?.applied?.providerBundleIdentifier,
            "com.avangard.vpn.network-extension"
        )
        XCTAssertEqual(TunnelStore.providerBundleIdentifier, "com.avangard.vpn.network-extension")
    }

    /// The cross-process contract: whatever the app writes, the extension has
    /// to be able to read back. `PacketTunnelProvider` does exactly this on
    /// startTunnel, and a mismatch there is a tunnel that refuses to start with
    /// no compile error anywhere.
    func testAppliedProviderConfigurationIsReadableByTheTunnel() async throws {
        let expected = config()
        await tunnel.connect(to: expected, regionName: "Singapore")

        let written = try XCTUnwrap(vpn.created?.applied?.providerConfiguration)
        let readBack = try XCTUnwrap(TunnelProfile(providerConfiguration: written))

        XCTAssertEqual(readBack, expected.profile)
    }

    func testAppliedSettingsNameTheRegionForTheSettingsApp() async {
        await connect()
        XCTAssertEqual(vpn.created?.applied?.localizedDescription, "AvangardVPN — Singapore")
    }

    // MARK: - Failures

    func testSaveFailureIsReportedAndNothingIsStarted() async {
        vpn.existing = [
            FakeVPNConfiguration(
                recorder: recorder,
                label: "existing",
                providerBundleIdentifier: TunnelStore.providerBundleIdentifier
            )
        ]
        vpn.existing[0].saveError = NEVPNError(.configurationReadWriteFailed)

        await connect()

        XCTAssertNotNil(tunnel.errorMessage)
        XCTAssertFalse(
            recorder.calls.contains("existing.start"),
            "a configuration that failed to save must not be started"
        )
    }

    /// Declining the system permission prompt comes back as
    /// configurationReadWriteFailed. It is the one failure the user can fix, so
    /// it must not fall through to the generic message.
    func testDeclinedPermissionGetsAnActionableMessage() {
        let message = TunnelStore.message(for: NEVPNError(.configurationReadWriteFailed))

        XCTAssertTrue(
            message.lowercased().contains("permission"),
            "expected the message to point at the permission prompt, got: \(message)"
        )
        XCTAssertNotEqual(message, TunnelStore.message(for: NEVPNError(.connectionFailed)))
    }

    /// Failing to read the preference store on appear is not something to greet
    /// the user with — they have not asked for anything yet.
    func testLoadFailureOnStartIsSilent() async {
        vpn.loadError = NEVPNError(.configurationReadWriteFailed)

        await tunnel.start()

        XCTAssertNil(tunnel.errorMessage)
        XCTAssertEqual(tunnel.status, .invalid)
    }

    // MARK: - Lifecycle

    /// The tunnel outlives the app. Reopening while it is up has to show
    /// "Connected", not offer to connect something already connected.
    func testStartAdoptsATunnelThatIsAlreadyRunning() async {
        let running = FakeVPNConfiguration(
            recorder: recorder,
            label: "running",
            providerBundleIdentifier: TunnelStore.providerBundleIdentifier
        )
        running.statusValue = .connected
        vpn.existing = [running]

        await tunnel.start()

        XCTAssertEqual(tunnel.status, .connected)
    }

    func testDisconnectStopsTheTunnel() async {
        await connect()
        tunnel.disconnect()

        XCTAssertTrue(recorder.calls.contains("new.stop"))
        XCTAssertEqual(tunnel.status, .disconnecting)
    }

    func testDisconnectWithoutAConfigurationDoesNothing() {
        tunnel.disconnect()
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    /// State changes the app did not cause — the user disconnecting from
    /// Settings, or the system dropping the tunnel — still have to reach the UI.
    func testStatusChangesFromTheSystemReachThePublishedStatus() async throws {
        await connect()
        vpn.created?.statusValue = .connected

        try await pumpStatusChanges(until: { self.tunnel.status == .connected })

        XCTAssertEqual(tunnel.status, .connected)
    }

    /// The observation task subscribes asynchronously, so a single emit can be
    /// posted before anything is listening. Emit until it lands.
    private func pumpStatusChanges(
        until condition: () -> Bool,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("status change never reached the store")
                return
            }
            vpn.emitStatusChange()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Pure helpers

    func testHostOfEndpointDropsThePort() {
        XCTAssertEqual(TunnelStore.host(of: "sg.example.com:51820"), "sg.example.com")
        XCTAssertEqual(TunnelStore.host(of: "203.0.113.9:51820"), "203.0.113.9")
        XCTAssertEqual(TunnelStore.host(of: "[2001:db8::1]:51820"), "2001:db8::1")
        // No port to strip, and splitting on ":" would truncate it to "2001".
        XCTAssertEqual(TunnelStore.host(of: "2001:db8::1"), "2001:db8::1")
        XCTAssertEqual(TunnelStore.host(of: "sg.example.com"), "sg.example.com")
    }

    func testEveryNEVPNStatusMapsToATunnelStatus() {
        XCTAssertEqual(TunnelStatus(.invalid), .invalid)
        XCTAssertEqual(TunnelStatus(.disconnected), .disconnected)
        XCTAssertEqual(TunnelStatus(.connecting), .connecting)
        XCTAssertEqual(TunnelStatus(.connected), .connected)
        XCTAssertEqual(TunnelStatus(.reasserting), .reasserting)
        XCTAssertEqual(TunnelStatus(.disconnecting), .disconnecting)
    }

    /// Reconnecting is not "connected": traffic is not flowing while it lasts,
    /// and the control has to keep offering a way out.
    func testReassertingIsTreatedAsAnInterruptionNotAsConnected() {
        XCTAssertTrue(TunnelStatus.reasserting.isTransitioning)
        XCTAssertTrue(TunnelStatus.reasserting.offersDisconnect)
        XCTAssertNotEqual(TunnelStatus.reasserting.title, TunnelStatus.connected.title)
    }

    /// A connect attempt that hangs is exactly when a user wants out.
    func testConnectingOffersAWayOut() {
        XCTAssertTrue(TunnelStatus.connecting.offersDisconnect)
        XCTAssertFalse(TunnelStatus.disconnected.offersDisconnect)
        XCTAssertFalse(TunnelStatus.invalid.offersDisconnect)
    }
}
