//
//  HomeView.swift — the connect screen.
//
//  One job: show whether the tunnel is up and let the user change that. The
//  connect control is the hero; everything else is supporting context.
//
//  The control is disabled and says why: the tunnel extension arrives in P3,
//  and it cannot run in the Simulator at all. Showing a live-looking button
//  that silently does nothing would be worse than showing an honest one.
//
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var provisioning: ProvisioningStore
    @State private var showRegionPicker = false

    private var activeRegion: Region? {
        provisioning.regions.first { $0.regionCode == provisioning.activeRegion }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                connectControl
                regionCard
                if let config = provisioning.activeTunnelConfig {
                    ConnectionDetailsCard(config: config)
                }
                if let message = provisioning.errorMessage {
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
                    .strokeBorder(Theme.separator, lineWidth: 1)
                    .frame(width: 176, height: 176)
                Image(systemName: "power")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.inkMuted)
            }

            VStack(spacing: 4) {
                Text("Not connected")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.inkPrimary)
                Text(provisioning.activeRegion == nil
                     ? "Choose a region to get started"
                     : "Tunnel support arrives in P3")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Button {
                // P3 wires this to the packet-tunnel extension.
            } label: {
                Text("Connect")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .background(Theme.brand.opacity(0.35), in: Capsule())
            .foregroundStyle(Theme.inkMuted)
            .disabled(true)
        }
        .padding(.top, 8)
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
