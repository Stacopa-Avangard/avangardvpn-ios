//
//  HomeView.swift — signed-in shell: region picker + provisioning state.
//
//  Still a working surface rather than the final design (that is P4). It shows
//  what P2 actually produced, including the assembled local config, so the
//  provisioning result is inspectable without a debugger.
//
import SwiftUI

struct HomeView: View {
    let user: AuthUser

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var provisioning = ProvisioningStore()
    @State private var showConfig = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        regionSection
                        if let config = provisioning.activeTunnelConfig {
                            activeConfigSection(config)
                        }
                        if let message = provisioning.errorMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        footer
                    }
                    .padding()
                }
            }
            .navigationTitle("Avangard VPN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task { await provisioning.loadRegions() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Signed in as")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(user.name)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(verbatim: user.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Regions")
                .font(.headline)
                .foregroundStyle(.white)

            if provisioning.isLoadingRegions && provisioning.regions.isEmpty {
                ProgressView().tint(.white)
            } else if provisioning.regions.isEmpty {
                Text("No regions available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(provisioning.regions) { region in
                    regionRow(region)
                }
            }
        }
    }

    private func regionRow(_ region: Region) -> some View {
        let isProvisioned = provisioning.provisionedRegions.contains(region.regionCode)
        let isActive = provisioning.activeRegion == region.regionCode
        let isBusy = provisioning.provisioningRegion == region.regionCode

        return Button {
            Task { await provisioning.provision(region) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "globe")
                    .foregroundStyle(isActive ? Color.brandPrimary : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(region.displayName)
                        .foregroundStyle(.white)
                    Text(isProvisioned ? "Ready on this device" : "Tap to set up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isBusy {
                    ProgressView().tint(.white)
                }
            }
            .padding()
            .background(.white.opacity(isActive ? 0.12 : 0.06),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isBusy)
    }

    private func activeConfigSection(_ config: TunnelConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active configuration")
                .font(.headline)
                .foregroundStyle(.white)

            configRow("Address", config.addresses.joined(separator: ", "))
            configRow("Endpoint", config.endpoint)
            configRow("Routes", config.allowedIps.joined(separator: ", "))
            configRow("DNS", config.dns.joined(separator: ", "))

            // The private key is never shown, and there is no way to export it.
            DisclosureGroup("Show wg-quick config", isExpanded: $showConfig) {
                Text(verbatim: redacted(config))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
            .tint(Color.brandPrimary)
            .foregroundStyle(.white)
            .font(.subheadline)
        }
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func configRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(verbatim: value)
                .font(.caption)
                .foregroundStyle(.white)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tunnel lands in P3")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Remove this device") {
                Task { await provisioning.revokeDevice() }
            }
            .font(.subheadline)
            .foregroundStyle(.red)

            Button("Sign out") {
                Task { await auth.signOut() }
            }
            .font(.subheadline)
            .foregroundStyle(Color.brandPrimary)
        }
        .padding(.top, 8)
    }

    /// Show the config the tunnel will use, with the two secrets masked. This
    /// view exists to make provisioning inspectable, not to export credentials.
    private func redacted(_ config: TunnelConfig) -> String {
        config.wgQuickConfig
            .replacingOccurrences(of: config.privateKey, with: "<private key held in Keychain>")
            .replacingOccurrences(of: config.presharedKey, with: "<preshared key>")
    }
}
