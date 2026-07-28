//
//  AvangardApp.swift — app entry point (SwiftUI lifecycle).
//
//  Routes between the sign-in flow and the signed-in shell. Provisioning (P2),
//  the tunnel (P3), and the real Home/Account/region-picker UI (P4) hang off
//  the signed-in branch.
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
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        switch auth.state {
        case .restoring:
            ZStack {
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        case .signedOut, .awaitingLink:
            LoginView()
        case let .signedIn(user):
            HomeView(user: user)
        }
    }
}

