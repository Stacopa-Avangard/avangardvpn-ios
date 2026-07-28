//
//  AccountView.swift — who you are, what you've used, which devices you have.
//
//  Also the only place destructive actions live. "Remove this device" revokes
//  every region at once (that is the granularity `/api/me/devices/:id` offers)
//  and drops the local keys, so it is behind a confirmation.
//
import SwiftUI

struct AccountView: View {
    let user: AuthUser

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var provisioning: ProvisioningStore

    @State private var usage: UsageSummary?
    @State private var devices: [DeviceSummary] = []
    @State private var loadError: String?
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                profileCard
                usageCard
                devicesCard
                actions
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Remove this device?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    await provisioning.revokeDevice()
                    await load()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This revokes every region set up on this device and deletes its keys. You can set it up again afterwards.")
        }
    }

    // MARK: - Cards

    private var profileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.inkPrimary)
                Text(verbatim: user.email)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                if user.isAdmin {
                    Label("Administrator", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var usageCard: some View {
        Card {
            if let usage {
                QuotaMeter(usage: usage)
            } else if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.statusCritical)
            } else {
                ProgressView().tint(Theme.inkPrimary)
            }
        }
    }

    private var devicesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Devices")

                if devices.isEmpty {
                    Text("No devices registered yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 {
                            Divider().overlay(Theme.separator)
                        }
                        deviceRow(device)
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: DeviceSummary) -> some View {
        let isThisDevice = device.deviceId == DeviceIdentity.id

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isThisDevice ? "iphone" : "desktopcomputer")
                .foregroundStyle(isThisDevice ? Theme.brand : Theme.inkMuted)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.deviceName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkPrimary)
                    if isThisDevice {
                        Text("This device")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Text(device.regions.isEmpty
                     ? "No regions"
                     : device.regions.joined(separator: ", ").uppercased())
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                confirmRemove = true
            } label: {
                Text("Remove this device")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(Theme.statusCritical)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))

            Button {
                Task { await auth.signOut() }
            } label: {
                Text("Sign out")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(Theme.brand)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }

    // MARK: - Loading

    private func load() async {
        // Usage and devices are independent; a failure in one shouldn't blank
        // the other, so they're fetched separately and reported together.
        async let usageResult = try? await APIClient.shared.usage()
        async let devicesResult = try? await APIClient.shared.devices()

        let (fetchedUsage, fetchedDevices) = await (usageResult, devicesResult)
        usage = fetchedUsage
        devices = fetchedDevices ?? []
        loadError = fetchedUsage == nil ? "Couldn't load your usage." : nil
    }
}
