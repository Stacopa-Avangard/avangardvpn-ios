//
//  HomeView.swift — the connect screen.
//
//  Laid out to match Android's HomeScreen.kt: a tracked caption, the region
//  chip, the orb filling the middle, then the status lines and the telemetry
//  strip. The orb IS the control — there is no separate Connect button, which
//  is the one interaction difference the two clients used to have.
//
//  What is deliberately NOT here any more: the connection-details card. Android
//  has no such thing on Home, and it is diagnostic rather than everyday, so it
//  moved to Account (see ConnectionDetailsCard there). It was not deleted —
//  with the tunnel not yet verified on real hardware, an inspectable config is
//  worth keeping somewhere.
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

    private var phase: ConnPhase { tunnel.status.phase }

    var body: some View {
        VStack(spacing: 0) {
            Text("SECURE TUNNEL")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.faint)
                .padding(.top, 18)

            regionChip
                .padding(.top, 10)

            if let usage = provisioning.usage {
                NearQuotaBanner(usage: usage)
            }

            centre
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if connectable != nil {
                statusText

                if let message = tunnel.errorMessage ?? provisioning.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.amber)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                telemetry
                    .padding(.top, 18)
            }

            Spacer().frame(height: Theme.bottomNavClearance)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await tunnel.start()
            await provisioning.refreshUsage()
        }
        .sheet(isPresented: $showRegionPicker) {
            RegionPickerView()
                .environmentObject(provisioning)
        }
    }

    // MARK: - Centre

    /// The middle of the screen is one of three things: the orb, a reason there
    /// is no orb yet, or the error that stopped us getting one.
    @ViewBuilder
    private var centre: some View {
        if connectable != nil {
            ConnectOrb(phase: phase, action: toggle)
        } else if provisioning.isLoadingRegions && provisioning.regions.isEmpty {
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.indigoBright)
                Text("Setting up your VPN…")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
        } else if let message = provisioning.errorMessage {
            retryBlock(
                title: "Couldn't set up your VPN",
                body: message,
                action: "Try again"
            ) {
                Task { await provisioning.loadRegions() }
            }
        } else {
            retryBlock(
                title: "No region set up yet",
                body: "Choose where this device should connect through.",
                action: "Choose a region"
            ) {
                showRegionPicker = true
            }
        }
    }

    private func retryBlock(
        title: String,
        body: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            GlassButton(title: action, action: perform)
                .padding(.top, 18)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Region chip

    private var regionChip: some View {
        Button {
            showRegionPicker = true
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(phase.accent(bright: true))
                    .frame(width: 7, height: 7)
                Text(activeRegion?.chipLabel ?? "No region")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                ChevronDownIcon(tint: Theme.muted, size: 18)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 9)
            .glass(cornerRadius: 50)
        }
        .buttonStyle(.plain)
        .accentCrossFade(phase)
    }

    // MARK: - Status

    private var statusText: some View {
        VStack(spacing: 5) {
            Text(headline)
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
    }

    /// `TunnelStatus.title` rather than Android's three-way switch: iOS can
    /// distinguish reconnecting from connecting and it would be a step
    /// backwards to collapse that.
    private var headline: String { tunnel.status.title }

    private var subtitle: String {
        let region = activeRegion?.displayName ?? "the server"
        switch tunnel.status {
        case .disconnected, .invalid:
            return "Tap the shield to protect this device"
        case .connecting:
            return "Exchanging keys with \(region)"
        case .connected:
            return "Your traffic is encrypted end-to-end"
        case .reasserting:
            return "The network changed — re-establishing the tunnel"
        case .disconnecting:
            return "Closing the tunnel"
        }
    }

    // MARK: - Telemetry

    @ViewBuilder
    private var telemetry: some View {
        if phase == .on {
            TelemetryStrip(
                throughput: tunnel.throughput,
                connectedSince: tunnel.connectedSince
            )
            .transition(.opacity)
        }
    }

    // MARK: - Actions

    private func toggle() {
        if tunnel.status.offersDisconnect {
            tunnel.disconnect()
            return
        }
        guard let config = connectable else { return }
        let name = activeRegion?.displayName ?? provisioning.activeRegion ?? "VPN"
        Task { await tunnel.connect(to: config, regionName: name) }
    }
}

// MARK: - Telemetry strip

/// DOWNLOAD / UPLOAD / SESSION, the same three cells as Android.
///
/// The clock is driven by a TimelineView off `connectedSince` rather than by a
/// counter this view increments. A counter would restart whenever the view is
/// recreated — a tab switch, a return from background — and report a session
/// far younger than the tunnel actually is.
struct TelemetryStrip: View {
    let throughput: Throughput
    let connectedSince: Date?

    var body: some View {
        HStack(spacing: 0) {
            cell("DOWNLOAD", ByteFormat.rate(throughput.downBytesPerSecond), Theme.indigoBright)
            divider
            cell("UPLOAD", ByteFormat.rate(throughput.upBytesPerSecond), Theme.emeraldBright)
            divider
            TimelineView(.periodic(from: .now, by: 1)) { context in
                cell("SESSION", elapsed(at: context.date), Theme.text)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glass()
    }

    private func cell(_ key: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 30)
    }

    private func elapsed(at now: Date) -> String {
        guard let connectedSince else { return "00:00" }
        let total = Int(max(0, now.timeIntervalSince(connectedSince)))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Near-quota banner

/// Only appears when there is something to say: over 80% used, or suspended.
/// Below that it would be noise on every launch.
struct NearQuotaBanner: View {
    let usage: UsageSummary

    private var shouldShow: Bool {
        !usage.unlimited && usage.quotaBytes > 0 && (usage.suspended || usage.fraction >= 0.8)
    }

    var body: some View {
        if shouldShow {
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(
                    (usage.suspended ? Theme.rose : Theme.amber).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.top, 14)
        }
    }

    private var message: String {
        if usage.suspended {
            return "You've hit your monthly limit. The VPN is paused until it resets."
        }
        return "You've used \(ByteFormat.string(usage.usedBytes)) of \(ByteFormat.string(usage.quotaBytes)) this month."
    }
}

// MARK: - Region presentation

extension Region {
    /// Flag + name, as Android's `Region.displayLabel()` builds it. The flag
    /// lives in the client so the server stays pure data; add a case when a
    /// region ships.
    var chipLabel: String {
        let flag: String
        switch regionCode {
        case "sg": flag = "🇸🇬"
        case "de": flag = "🇩🇪"
        default: flag = "🌐"
        }
        return "\(flag)  \(displayName)"
    }
}
