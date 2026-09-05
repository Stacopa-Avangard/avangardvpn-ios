//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  Theme.swift — the app's visual tokens.
//
//  A port of the Android client's "security console" design system
//  (`ui/theme/Theme.kt` there), so the two platforms are one product with one
//  face rather than two apps that happen to share a backend. The palette, the
//  phase→accent ramp and the glass treatment are all deliberately the SAME
//  values as Android; changing one without the other is what makes them drift.
//
//  The app is dark-only, like Android. These are picked against the near-black
//  indigo-biased ground below, not flipped from a light set.
//
import SwiftUI

enum Theme {

    // MARK: - Raw palette
    //
    // ⚠️ Kept numerically identical to Android's `Theme.kt`. If one moves, move
    // both — a "close enough" hex here is exactly how the two clients stopped
    // looking like the same product before.

    /// `#090B12` — the ground. Not true black: it carries a slight indigo bias
    /// so the accent glows sit in the same family as the background.
    static let ground = Color(hex: 0x090B12)
    /// `#0B0E18` — raised ground, for sheets that must separate from the page.
    static let ground2 = Color(hex: 0x0B0E18)

    static let indigo = Color(hex: 0x6366F1)
    static let indigoBright = Color(hex: 0x8E92FF)
    static let emerald = Color(hex: 0x10B981)
    static let emeraldBright = Color(hex: 0x34D399)
    static let amber = Color(hex: 0xF59E0B)
    static let amberBright = Color(hex: 0xFB923C)
    static let rose = Color(hex: 0xF43F5E)

    // MARK: - Brand mark
    //
    // The app-icon gradient, and the only place `#0D6EFD` belongs. Android uses
    // that blue for the launcher icon, its old material seed, and the shield
    // mark on the sign-in screen — NOT as a UI primary. The interface primary
    // on both clients is `indigo` above. iOS used to paint every control
    // `#0D6EFD` under a comment claiming it was Android's primary, which is how
    // the two clients ended up different colours.

    static let markStart = Color(hex: 0x312E81)
    static let markEnd = Color(hex: 0x0D6EFD)

    // MARK: - Ink
    //
    // Text always wears these, never a data colour — a coloured mark sitting
    // beside a label is what carries meaning.

    static let text = Color(hex: 0xEAEEF6)
    static let muted = Color(hex: 0x8A93A8)
    static let faint = Color(hex: 0x59617A)

    // MARK: - Surfaces

    static let stroke = Color.white.opacity(0.09)
    static let strokeStrong = Color.white.opacity(0.15)
    static let glassTop = Color.white.opacity(0.075)
    static let glassBottom = Color.white.opacity(0.04)

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let stackSpacing: CGFloat = 18
    /// Height of the floating bottom bar plus its padding. Screens add this as
    /// bottom inset so their last row is not sitting underneath the nav.
    static let bottomNavClearance: CGFloat = 104
}

// MARK: - Connection phase → accent

/// The three states the whole interface is coloured by. Deliberately coarser
/// than `TunnelStatus`: the accent answers "am I protected", while the label
/// under the orb carries the precise wording.
enum ConnPhase: Equatable {
    case off, connecting, on
}

extension TunnelStatus {
    var phase: ConnPhase {
        switch self {
        case .connected: return .on
        // Everything mid-flight is amber, tearing down included. Traffic is not
        // flowing during any of them, and a user watching the orb should see
        // that rather than a colour that says "protected".
        case .connecting, .reasserting, .disconnecting: return .connecting
        case .disconnected, .invalid: return .off
        }
    }
}

extension ConnPhase {
    /// Accent for this phase. `bright` is the higher-chroma step, used for
    /// marks that sit ON the accent glow rather than beside it.
    func accent(bright: Bool = false) -> Color {
        switch self {
        case .off: return bright ? Theme.indigoBright : Theme.indigo
        case .connecting: return bright ? Theme.amberBright : Theme.amber
        case .on: return bright ? Theme.emeraldBright : Theme.emerald
        }
    }
}

/// The cross-fade Android gets from `animateColorAsState(tween(500))`.
/// Applied at the view that renders an accent, not stored on the colour.
extension View {
    func accentCrossFade(_ phase: ConnPhase) -> some View {
        animation(.easeInOut(duration: 0.5), value: phase)
    }
}

// MARK: - Surface treatments

/// Glassmorphism panel: translucent vertical gradient + hairline border.
/// The direct port of Android's `Modifier.glass`.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Theme.glassTop, Theme.glassBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

/// Ambient background: the ground with two accent-tinted radial glows, one
/// bleeding down from the top and a weaker one up from the bottom. This is the
/// single element that makes the whole app react to the connection state, so
/// it lives behind everything rather than inside a screen.
struct AmbientWash: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Theme.ground
                RadialGradient(
                    colors: [accent.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.5, y: 0.02),
                    startRadius: 0,
                    endRadius: h * 0.6
                )
                RadialGradient(
                    colors: [accent.opacity(0.11), .clear],
                    center: UnitPoint(x: 0.5, y: 1.02),
                    startRadius: 0,
                    endRadius: h * 0.55
                )
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func glass(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Shared building blocks

/// A glass card. Every grouped block on a screen uses this so elevation and
/// corner radius never drift between views.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
    }
}

/// Section heading above a group of cards. The all-caps tracked label Android
/// uses for the same job.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(2)
            .foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Hex

extension Color {
    /// `Color(hex: 0x6366F1)` — so the tokens above can be read against
    /// Android's `Color(0xFF6366F1)` at a glance.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
