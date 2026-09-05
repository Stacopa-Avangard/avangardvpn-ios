//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  AvangardApp.swift — app entry point (SwiftUI lifecycle).
//
//  Routes between the splash, the sign-in flow and the signed-in shell.
//
//  The shell is a ZStack rather than a NavigationStack + TabView, matching
//  Android's RootScreen: the ambient wash sits behind everything and reacts to
//  the connection phase, the screen floats on top of it, and the glass nav bar
//  floats over both. A system tab bar would paint an opaque strip over the
//  bottom glow and undo the effect.
//
import SwiftUI

@main
struct AvangardVPNApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task { await auth.restore() }
                .preferredColorScheme(.dark)
                .tint(Theme.indigo)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    /// Read here rather than inside the gate so agreeing re-renders this switch.
    @AppStorage(DataDisclosure.storageKey) private var disclosureAccepted = 0

    var body: some View {
        switch auth.state {
        case .restoring:
            // The brand splash, on the same beat Android shows it — a cold
            // launch reads as the product rather than as a bare spinner.
            SplashView()
        case .signedOut, .awaitingLink:
            ZStack {
                // Nothing is connected before sign-in, so the wash is fixed at
                // the idle accent.
                AmbientWash(accent: ConnPhase.off.accent())

                // Guideline 5.4 wants the data declaration on an app screen
                // "prior to any user action to ... use the service", and the
                // first action here — typing an email and asking for a link —
                // already sends data. So the gate sits in front of LoginView
                // rather than in front of Connect. See DataDisclosureView.
                if disclosureAccepted >= DataDisclosure.version {
                    LoginView()
                } else {
                    DataDisclosureView()
                }
            }
        case let .signedIn(user):
            SignedInShell(user: user)
        }
    }
}

/// Two tabs: connect, and everything about the account.
///
/// `ProvisioningStore` is owned here rather than inside a tab so both tabs see
/// the same region and quota state — Account's "remove this device" has to be
/// reflected on Home immediately.
struct SignedInShell: View {
    let user: AuthUser

    @StateObject private var provisioning = ProvisioningStore()

    /// Owned at the shell for the same reason, plus one of its own: a store
    /// recreated whenever HomeView appears would re-read the system
    /// configuration each time and flash "Not connected" over a tunnel that is
    /// already up. It also owns the session clock, which must not restart when
    /// the user visits Account and comes back.
    @StateObject private var tunnel = TunnelStore()

    @State private var tab: AppTab = .initial

    var body: some View {
        ZStack(alignment: .bottom) {
            AmbientWash(accent: tunnel.status.phase.accent())
                .accentCrossFade(tunnel.status.phase)

            Group {
                switch tab {
                case .home: HomeView()
                case .account: AccountView(user: user)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomNav(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .environmentObject(provisioning)
        .environmentObject(tunnel)
        .task { await provisioning.loadRegions() }
    }
}

extension AppTab {
    /// Which tab the app opens on. DEBUG builds can be pointed at a specific
    /// one (`AVANGARD_DEV_TAB=account`) so a screen can be launched and
    /// screenshotted directly, without tapping through.
    static var initial: AppTab {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AVANGARD_DEV_TAB"] == "account" {
            return .account
        }
        #endif
        return .home
    }
}
