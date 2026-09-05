//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  RegionPickerView.swift — choose (and provision) a region.
//
//  Presented as a bottom sheet on the raised ground, matching Android's
//  `RegionPickerSheet`: a tracked caption, then one row per region with an
//  emerald dot on the active one.
//
//  Picking a region that this device has never used registers it: mint a
//  keypair, upload the public half, keep the reply. That is a network call, so
//  each row owns its own busy state rather than blocking the whole sheet —
//  which is the one thing this sheet does that Android's does not, because
//  Android provisions its single region up front.
//
import SwiftUI

struct RegionPickerView: View {
    @EnvironmentObject private var provisioning: ProvisioningStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The ground is painted with a ZStack rather than
        // `.presentationBackground`, which is iOS 16.4 and this app deploys to
        // 16.0. Same result: the sheet reads as the raised ground, not as the
        // system's default material.
        ZStack {
            Theme.ground2.ignoresSafeArea()
            sheet
        }
        .presentationDetents([.medium])
        .task {
            if provisioning.regions.isEmpty {
                await provisioning.loadRegions()
            }
        }
    }

    private var sheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Choose region")
                    .padding(.bottom, 4)

                if provisioning.isLoadingRegions && provisioning.regions.isEmpty {
                    ProgressView()
                        .tint(Theme.indigoBright)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if provisioning.regions.isEmpty {
                    Text("No regions are available right now.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 40)
                } else {
                    ForEach(provisioning.regions) { region in
                        row(region)
                    }
                }

                if let message = provisioning.errorMessage {
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.amber)
                        .padding(.top, 8)
                }

                Text("Setting up a region creates a key on this device. The private key never leaves it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ region: Region) -> some View {
        let isActive = provisioning.activeRegion == region.regionCode
        let isProvisioned = provisioning.provisionedRegions.contains(region.regionCode)
        let isBusy = provisioning.provisioningRegion == region.regionCode

        return Button {
            Task {
                await provisioning.provision(region)
                if provisioning.errorMessage == nil { dismiss() }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.chipLabel)
                        .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                    if !isProvisioned {
                        Text("Tap to set up")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                    }
                }

                Spacer()

                if isBusy {
                    ProgressView().tint(Theme.indigoBright)
                } else if isActive {
                    Circle()
                        .fill(Theme.emeraldBright)
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
