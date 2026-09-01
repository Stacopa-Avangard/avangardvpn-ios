//
//  ProvisioningStore.swift — region catalogue + device registration.
//
//  Provisioning a region means: mint a keypair for it (if this device has none
//  yet), upload the public half, and keep the server's reply so a complete
//  tunnel config can be assembled locally. TunnelStore is what hands that
//  config to the tunnel extension; nothing here starts a tunnel.
//
import Foundation

@MainActor
final class ProvisioningStore: ObservableObject {
    @Published private(set) var regions: [Region] = []
    @Published private(set) var isLoadingRegions = false
    /// Region code currently being registered, for a per-row spinner.
    @Published private(set) var provisioningRegion: String?
    @Published private(set) var provisionedRegions: Set<String> = []
    /// The region the user last provisioned — what the tunnel connects to.
    @Published private(set) var activeRegion: String?

    /// Bandwidth against the monthly quota. Owned here rather than by a screen
    /// because both tabs render it — Home as a near-quota banner, Account as
    /// the meter — and two independent fetches would let them disagree.
    @Published private(set) var usage: UsageSummary?
    @Published var errorMessage: String?

    private let activeRegionKey = "provisioning.activeRegion"

    init() {
        activeRegion = UserDefaults.standard.string(forKey: activeRegionKey)
    }

    func loadRegions() async {
        isLoadingRegions = true
        defer { isLoadingRegions = false }

        do {
            let fetched = try await APIClient.shared.regions()
            regions = fetched
            // Reconcile against what this device actually holds credentials
            // for — the source of truth is the Keychain, not the catalogue.
            provisionedRegions = Set(fetched.map(\.regionCode).filter { PeerStore.provisioned($0) != nil })

            if let active = activeRegion, !provisionedRegions.contains(active) {
                // Stored choice no longer has credentials (device revoked
                // elsewhere, region deactivated) — drop it.
                setActiveRegion(nil)
            }
            if activeRegion == nil {
                // Holding credentials but nothing marked active leaves the UI
                // saying "ready" with no tunnel selected. Adopt a provisioned
                // region in catalogue order so the state is always coherent.
                setActiveRegion(fetched.map(\.regionCode).first { provisionedRegions.contains($0) })
            }
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Best-effort: a usage fetch that fails leaves the previous figure up
    /// rather than blanking it, exactly as Android's `refreshUsage` does. A
    /// stale number is more useful than no number, and the period label says
    /// which month it belongs to.
    func refreshUsage() async {
        if let fetched = try? await APIClient.shared.usage() {
            usage = fetched
        }
    }

    func provision(_ region: Region) async {
        provisioningRegion = region.regionCode
        defer { provisioningRegion = nil }

        do {
            let response = try await APIClient.shared.provision(regionCode: region.regionCode)
            try PeerStore.save(response)
            provisionedRegions.insert(region.regionCode)
            setActiveRegion(region.regionCode)
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Revoke this device server-side (every region at once — that is the only
    /// granularity `/api/me/devices/:id` offers) and drop the local keys.
    func revokeDevice() async {
        do {
            try await APIClient.shared.revokeDevice(DeviceIdentity.id)
        } catch APIError.http(status: 404, code: _) {
            // Nothing registered server-side; local cleanup below still applies.
        } catch {
            errorMessage = message(for: error)
            return
        }

        PeerStore.forgetAll(regions: regions.map(\.regionCode))
        provisionedRegions.removeAll()
        setActiveRegion(nil)
        errorMessage = nil
    }

    /// The assembled config for the active region — proof the local half is
    /// complete. TunnelStore writes it into the saved VPN configuration.
    var activeTunnelConfig: TunnelConfig? {
        guard let activeRegion else { return nil }
        return PeerStore.tunnelConfig(for: activeRegion)
    }

    private func setActiveRegion(_ code: String?) {
        activeRegion = code
        if let code {
            UserDefaults.standard.set(code, forKey: activeRegionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeRegionKey)
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
