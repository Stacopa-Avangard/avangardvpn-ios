//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  AccountView.swift — who you are, what you've used, which devices you have.
//
//  Laid out to match Android's AccountScreen.kt: the avatar header, the quota
//  card, the device list, the legal links, then sign out and — quieter than it,
//  deliberately — account deletion.
//
//  Two things live here that Android keeps elsewhere or not at all:
//
//   - the connection details card, moved off Home (Android's Home has no such
//     card). It is diagnostic rather than everyday, and worth keeping while the
//     tunnel has not been verified on real hardware.
//   - nothing else. If a control is not on Android's Account screen and not in
//     that list, it does not belong here either.
//
import SwiftUI

/// The server's cap, copied. It is NOT sent to the app, so this number goes
/// stale — Android's copy said 5 until production moved to a uniform 3 in
/// migration 011. If plans ever carry different caps, stop copying it: have
/// `GET /api/me/devices` return the cap and read it from there.
private let deviceCap = 3

struct AccountView: View {
    let user: AuthUser

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var provisioning: ProvisioningStore
    @EnvironmentObject private var tunnel: TunnelStore
    @Environment(\.openURL) private var openURL

    @State private var devices: [DeviceSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 14)

                Card { QuotaMeter(usage: provisioning.usage) }
                    .padding(.top, 22)

                devicesCard
                    .padding(.top, 14)

                if let config = provisioning.activeTunnelConfig {
                    ConnectionDetailsCard(config: config)
                        .padding(.top, 14)
                }

                legalCard
                    .padding(.top, 14)

                GlassButton(title: "Sign out", danger: true) {
                    Task { await auth.signOut() }
                }
                .padding(.top, 20)

                // Kept visible rather than hidden behind a menu — Apple wants
                // deletion reachable in-app. It is deliberately quieter than
                // Sign out: the more destructive of the two should not be the
                // easier to hit.
                Button {
                    deleteError = nil
                    showDelete = true
                } label: {
                    Text("Delete account")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.rose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)

                Text("Powered by Avangard")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                Spacer().frame(height: Theme.bottomNavClearance)
            }
            .padding(.horizontal, 22)
        }
        .scrollContentBackground(.hidden)
        /*
          A scrim under the status bar. This screen scrolls edge-to-edge, so a
          card heading slides up behind the clock and the Dynamic Island and
          collides with them — white-on-dark against white-on-dark, with nothing
          between. Android needs no equivalent: its status bar sits on an opaque
          strip.

          Deliberately a gradient to transparent rather than a solid bar: the
          ambient wash is at its brightest along the top edge, and a solid strip
          would cut the glow off in a straight line across the screen.
        */
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Theme.ground.opacity(0.92), Theme.ground.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 54)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showDelete) {
            DeleteAccountSheet(
                email: user.email,
                busy: isDeleting,
                error: deleteError,
                onConfirm: { Task { await deleteAccount() } },
                onCancel: {
                    showDelete = false
                    deleteError = nil
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 13) {
            Text(String(user.email.first.map(Character.init) ?? "A").uppercased())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [Theme.indigo, Color(hex: 0x4338CA)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: user.email)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(memberLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()
        }
    }

    /// With no device list loaded there is no count to state. "0 of 3" would be
    /// inventing one, and 0 is exactly the number a user would act on.
    private var memberLine: String {
        if loadError != nil && devices.isEmpty {
            return "Member · \(deviceCap) devices max"
        }
        return "Member · \(devices.count) of \(deviceCap) devices"
    }

    // MARK: - Devices

    private var devicesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHead(title: "Devices", aside: devicesAside)
                    .padding(.bottom, 6)

                if devices.isEmpty {
                    // "No devices yet." is a claim about the account. Only make
                    // it when the list actually loaded — otherwise say what
                    // really happened.
                    Text(emptyDevicesMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(loadError != nil && !isLoading ? Theme.amber : Theme.muted)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.stroke)
                                .frame(height: 1)
                        }
                        deviceRow(device)
                    }
                }
            }
        }
    }

    private var devicesAside: String {
        if isLoading { return "…" }
        if loadError != nil && devices.isEmpty { return "unavailable" }
        return "\(devices.count) active"
    }

    private var emptyDevicesMessage: String {
        if isLoading { return "Loading…" }
        if let loadError { return loadError }
        return "No devices yet."
    }

    private func deviceRow(_ device: DeviceSummary) -> some View {
        let isCurrent = device.deviceId == DeviceIdentity.id

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    if isCurrent {
                        Circle()
                            .fill(Theme.emeraldBright)
                            .frame(width: 6, height: 6)
                    }
                    Text(isCurrent ? "\(device.deviceName) · This device" : device.deviceName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                }
                if !device.regions.isEmpty {
                    Text(verbatim: device.regions.joined(separator: ", ").uppercased())
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                }
            }

            Spacer()

            Button {
                Task { await revoke(device) }
            } label: {
                Text("Remove")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
    }

    // MARK: - Legal

    /// In-app legal links. App Store Review wants a privacy policy reachable
    /// from inside the app, not only from the store listing — this is that.
    private var legalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHead(title: "Legal", aside: "opens in browser")
                    .padding(.bottom, 4)

                legalRow("Privacy Policy", url: LegalUrls.privacy)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                legalRow("Terms of Service", url: LegalUrls.terms)
            }
        }
    }

    private func legalRow(_ label: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(verbatim: "↗")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Usage and devices are independent; a failure in one shouldn't blank
        // the other, so they're fetched separately and reported separately.
        async let usageRefresh: Void = provisioning.refreshUsage()
        async let fetchedDevices = try? await APIClient.shared.devices()

        let (_, list) = await (usageRefresh, fetchedDevices)
        if let list {
            devices = list
            loadError = nil
        } else {
            loadError = "Couldn't load your devices."
        }
    }

    /// Revoking THIS device also has to drop the local keys, which only
    /// ProvisioningStore can do. Revoking another one is a plain API call — its
    /// keys live on that device, not here.
    private func revoke(_ device: DeviceSummary) async {
        if device.deviceId == DeviceIdentity.id {
            tunnel.disconnect()
            await provisioning.revokeDevice()
        } else {
            try? await APIClient.shared.revokeDevice(device.deviceId)
        }
        await load()
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        // The server takes the peers off the interface before it replies, so a
        // request travelling through our own tunnel can lose its return path.
        tunnel.disconnect()

        if let message = await auth.deleteAccount() {
            deleteError = message
            return
        }
        // On success the auth state moved to signedOut and this view is gone;
        // dismissing the sheet is only tidiness for the frame in between.
        showDelete = false
    }
}

// MARK: - Connection details

/// The address this device holds on the tunnel, and nothing else.
///
/// Endpoint, routes, DNS and the wg-quick dump used to sit here too. They named
/// the transport plainly enough to read as "this is WireGuard", which is not
/// how the product presents itself, so they are gone. Nothing about the tunnel
/// changed — only what the screen admits to.
///
/// ⚠️ An "IPv4 only" notice went with them. It was the one place a user could
/// see that a region has no v6 address assigned — a condition that black-holes
/// v6 traffic silently: no error, just some sites that never load. The
/// condition is not gone, only unreported. If it ever bites, the truth is
/// `allowedIps` in TunnelConfig, not this view.
struct ConnectionDetailsCard: View {
    let config: TunnelConfig

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHead(title: "Connection", aside: "this device")

                detail("Address", config.addresses.joined(separator: ", "))
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .frame(width: 68, alignment: .leading)
            Text(verbatim: value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
        }
    }
}
