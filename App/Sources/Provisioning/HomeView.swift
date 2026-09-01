//
//  HomeView.swift — the connect screen.
//
//  One job: show whether the tunnel is up and let the user change that. The
//  connect control is the hero; everything else is supporting context.
//
//  The control is live as of P4. It is still disabled when there is nothing to
//  connect to — no region provisioned means no config to hand the extension —
//  and it says which of the two it is rather than just going grey.
//
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var provisioning: ProvisioningStore
    @EnvironmentObject private var tunnel: TunnelStore
    @State private var showRegionPicker = false

    private var activeRegion: Region? {
        provisioning.regions.first { $0.regionCode == provisioning.activeRegion }
    }

    /// Both halves have to be present to connect: a region the user picked, and
    /// credentials this device actually holds for it.
    private var connectable: TunnelConfig? {
        provisioning.activeTunnelConfig
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                connectControl
                regionCard
                if let config = provisioning.activeTunnelConfig {
                    ConnectionDetailsCard(config: config)
                }
                if let message = tunnel.errorMessage ?? provisioning.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.statusCritical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Avangard VPN")
        .navigationBarTitleDisplayMode(.inline)
        .task { await tunnel.start() }
        .sheet(isPresented: $showRegionPicker) {
            RegionPickerView()
                .environmentObject(provisioning)
        }
    }

    // MARK: - Hero

    private var connectControl: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 176, height: 176)
                Circle()
                    .strokeBorder(dialColor.opacity(0.9), lineWidth: 2)
                    .frame(width: 176, height: 176)
                Image(systemName: "power")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(dialColor)
            }
            // The dial is the only thing on screen that moves, so the state
            // change reads even when the label is not being watched.
            .animation(.easeInOut(duration: 0.2), value: tunnel.status)

            VStack(spacing: 4) {
                Text(tunnel.status.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.inkPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: toggle) {
                Group {
                    if tunnel.isPreparing || tunnel.status == .disconnecting {
                        ProgressView().tint(Theme.inkPrimary)
                    } else {
                        Text(tunnel.status.offersDisconnect ? "Disconnect" : "Connect")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .background(canToggle ? Theme.brand : Theme.brand.opacity(0.35), in: Capsule())
            .foregroundStyle(canToggle ? Theme.inkPrimary : Theme.inkMuted)
            .disabled(!canToggle)
        }
        .padding(.top, 8)
    }

    private var dialColor: Color {
        switch tunnel.status {
        case .connected: return Theme.statusGood
        // Reconnecting is not a healthy green: traffic is not flowing while it
        // lasts, and a user watching the dial should see that something is off.
        case .connecting, .reasserting: return Theme.statusWarning
        case .disconnecting: return Theme.inkSecondary
        case .disconnected, .invalid: return Theme.inkMuted
        }
    }

    private var subtitle: String {
        if provisioning.activeRegion == nil {
            return "Choose a region to get started"
        }
        if connectable == nil {
            return "This region is not set up on this device yet"
        }
        switch tunnel.status {
        case .connected, .reasserting:
            return activeRegion.map { "Routing through \($0.displayName)" } ?? "Tunnel up"
        default:
            return activeRegion.map { "Ready to connect to \($0.displayName)" } ?? "Ready to connect"
        }
    }

    /// Disabled while a request is in flight, and while the system is tearing
    /// the tunnel down — a second tap there does nothing but look broken.
    private var canToggle: Bool {
        connectable != nil && !tunnel.isPreparing && tunnel.status != .disconnecting
    }

    private func toggle() {
        if tunnel.status.offersDisconnect {
            tunnel.disconnect()
            return
        }
        guard let config = connectable else { return }
        let name = activeRegion?.displayName ?? provisioning.activeRegion ?? "VPN"
        Task { await tunnel.connect(to: config, regionName: name) }
    }

    // MARK: - Region

    private var regionCard: some View {
        Button {
            showRegionPicker = true
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundStyle(Theme.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Region")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                        Text(activeRegion?.displayName ?? "Not selected")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.inkPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// What the tunnel will actually use. Kept visible because a wrong route or a
/// missing IPv6 address is invisible until traffic silently breaks.
struct ConnectionDetailsCard: View {
    let config: TunnelConfig
    @State private var expanded = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Connection")

                detail("Address", config.addresses.joined(separator: ", "))
                detail("Endpoint", config.endpoint)
                detail("Routes", config.allowedIps.joined(separator: ", "))
                detail("DNS", config.dns.joined(separator: ", "))

                if !config.allowedIps.contains(where: { $0.contains(":") }) {
                    Label("IPv4 only — this region has no IPv6 assigned", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }

                DisclosureGroup("Show wg-quick config", isExpanded: $expanded) {
                    Text(verbatim: redacted)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
                .font(.caption)
                .tint(Theme.brand)
                .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 68, alignment: .leading)
            Text(verbatim: value)
                .font(.caption)
                .foregroundStyle(Theme.inkPrimary)
        }
    }

    /// Secrets are masked. This view exists to make the config inspectable,
    /// not to export credentials — there is no path that reveals the keys.
    private var redacted: String {
        config.wgQuickConfig
            .replacingOccurrences(of: config.privateKey, with: "<private key — stays in Keychain>")
            .replacingOccurrences(of: config.presharedKey, with: "<preshared key>")
    }
}
