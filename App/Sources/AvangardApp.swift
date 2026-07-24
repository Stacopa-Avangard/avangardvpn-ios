//
//  AvangardApp.swift — app entry point (SwiftUI lifecycle).
//  P0 walking skeleton: shows a placeholder. Real Home/Account/region-picker UI
//  arrives in P4; auth (P1), provisioning (P2), and the tunnel (P3) come first.
//
import SwiftUI

@main
struct AvangardVPNApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                Text("Avangard VPN")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("iOS — scaffold (P0)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    RootView()
}
