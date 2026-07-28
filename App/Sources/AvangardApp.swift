//
//  AvangardApp.swift — app entry point (SwiftUI lifecycle).
//
//  Routes between the sign-in flow and the signed-in shell. The tunnel itself
//  (P3) hangs off the Home tab.
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
                .tint(Theme.brand)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        switch auth.state {
        case .restoring:
            ZStack {
                Theme.background.ignoresSafeArea()
                ProgressView().tint(Theme.inkPrimary)
            }
        case .signedOut, .awaitingLink:
            LoginView()
        case let .signedIn(user):
            SignedInShell(user: user)
        }
    }
}

/// Two tabs: connect, and everything about the account.
///
/// `ProvisioningStore` is owned here rather than inside a tab so both tabs see
/// the same region state — Account's "remove this device" has to be reflected
/// on Home immediately.
struct SignedInShell: View {
    let user: AuthUser

    @StateObject private var provisioning = ProvisioningStore()
    @State private var tab: Tab = .initial

    enum Tab: Hashable {
        case connect, account

        /// Which tab the app opens on. DEBUG builds can be pointed at a
        /// specific one (`AVANGARD_DEV_TAB=account`) so a screen can be
        /// launched and screenshotted directly, without tapping through.
        static var initial: Tab {
            #if DEBUG
            if ProcessInfo.processInfo.environment["AVANGARD_DEV_TAB"] == "account" {
                return .account
            }
            #endif
            return .connect
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Connect", systemImage: "shield.lefthalf.filled") }
            .tag(Tab.connect)

            NavigationStack {
                AccountView(user: user)
            }
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
            .tag(Tab.account)
        }
        .environmentObject(provisioning)
        .task { await provisioning.loadRegions() }
    }
}
