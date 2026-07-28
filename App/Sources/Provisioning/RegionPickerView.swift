//
//  RegionPickerView.swift — choose (and provision) a region.
//
//  Picking a region that this device has never used registers it: mint a
//  keypair, upload the public half, keep the reply. That is a network call, so
//  each row owns its own busy state rather than blocking the whole sheet.
//
import SwiftUI

struct RegionPickerView: View {
    @EnvironmentObject private var provisioning: ProvisioningStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if provisioning.isLoadingRegions && provisioning.regions.isEmpty {
                        ProgressView()
                            .tint(Theme.inkPrimary)
                            .padding(.top, 40)
                    } else if provisioning.regions.isEmpty {
                        Text("No regions are available right now.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(provisioning.regions) { region in
                            row(region)
                        }
                    }

                    if let message = provisioning.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.statusCritical)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }

                    Text("Setting up a region creates a key on this device. The private key never leaves it.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Theme.brand)
                }
            }
        }
        .task {
            if provisioning.regions.isEmpty {
                await provisioning.loadRegions()
            }
        }
    }

    private func row(_ region: Region) -> some View {
        let isProvisioned = provisioning.provisionedRegions.contains(region.regionCode)
        let isActive = provisioning.activeRegion == region.regionCode
        let isBusy = provisioning.provisioningRegion == region.regionCode

        return Button {
            Task {
                await provisioning.provision(region)
                if provisioning.errorMessage == nil { dismiss() }
            }
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "globe")
                        .foregroundStyle(isActive ? Theme.brand : Theme.inkMuted)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.inkPrimary)
                        Text(isProvisioned ? "Set up on this device" : "Tap to set up")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    Spacer()

                    if isBusy {
                        ProgressView().tint(Theme.inkPrimary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
