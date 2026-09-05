//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  SplashView.swift — the brand splash, ported from Android's SplashScreen.kt.
//
//  A blue radial glow over near-black, the white Avangard shield, and the
//  wordmark. Shown while the session is being restored, which is the same beat
//  Android shows it on — so a cold launch looks the same on both platforms
//  instead of iOS flashing a bare spinner.
//
//  Note this ground is NOT Theme.ground: the splash is the one screen that is
//  brand-blue rather than console-dark, on both clients.
//
import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            RadialGradient(
                stops: [
                    .init(color: Color(hex: 0x2C6BF0), location: 0.0),
                    .init(color: Color(hex: 0x163C9E), location: 0.32),
                    .init(color: Color(hex: 0x0A1633), location: 0.66),
                    .init(color: Color(hex: 0x04060E), location: 1.0),
                ],
                center: .center,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                ShieldShape()
                    .fill(.white)
                    .frame(width: 132, height: 132)

                Text("AVANGARD VPN")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AvangardVPN")
    }
}
