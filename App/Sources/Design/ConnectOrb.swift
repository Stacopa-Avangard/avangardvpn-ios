//
//  ConnectOrb.swift — the signature element, ported from Android's ConnectOrb.kt.
//
//  A concentric-ring reactor whose glow and accent track the connection phase:
//  steady indigo when off, an amber spinner while the handshake runs, a
//  breathing emerald glow once the tunnel is up.
//
//  The orb IS the control — the whole 260pt disc is the tap target, as on
//  Android. There is no separate "Connect" button underneath it.
//
//  On the animation: the two clocks come from `TimelineView(.animation)` rather
//  than from `repeatForever` state animations. A repeating animation has to be
//  started, restarted when the phase changes, and torn down; a function of the
//  timeline is none of those things and cannot desynchronise from itself. The
//  idle phase renders without a TimelineView at all, so a screen sitting at
//  "Not connected" is not repainting at 60fps in the user's pocket.
//
import SwiftUI

struct ConnectOrb: View {
    let phase: ConnPhase
    let action: () -> Void

    /// Matches Android: 260dp overall, a 176dp core, a 58dp glyph.
    private let diameter: CGFloat = 260
    private let coreDiameter: CGFloat = 176
    private let glyphDiameter: CGFloat = 58

    var body: some View {
        Button(action: action) {
            Group {
                if phase == .off {
                    // Nothing moves in this phase — draw it once.
                    orb(glowAlpha: 0.5, spin: 0)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        orb(glowAlpha: glowAlpha(at: t), spin: spin(at: t))
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accentCrossFade(phase)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Drawing

    private func orb(glowAlpha: Double, spin: Double) -> some View {
        ZStack {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) / 2

                // Ambient glow.
                context.fill(
                    Path(ellipseIn: square(around: c, radius: outer)),
                    with: .radialGradient(
                        Gradient(colors: [accent.opacity(glowAlpha), .clear]),
                        center: c,
                        startRadius: 0,
                        endRadius: outer
                    )
                )

                // Static concentric rings.
                context.stroke(
                    Path(ellipseIn: square(around: c, radius: outer - 1)),
                    with: .color(Theme.stroke),
                    lineWidth: 1
                )
                context.stroke(
                    Path(ellipseIn: square(around: c, radius: outer - 26)),
                    with: .color(Theme.stroke.opacity(0.45)),
                    lineWidth: 1
                )

                // Handshake spinner — a 90° arc chasing its own tail.
                if phase == .connecting {
                    let r = outer - 8
                    var arc = Path()
                    arc.addArc(
                        center: c,
                        radius: r,
                        startAngle: .degrees(spin),
                        endAngle: .degrees(spin + 90),
                        clockwise: false
                    )
                    context.stroke(
                        arc,
                        with: .color(accentBright),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }
            }

            core
        }
    }

    private var core: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x141826), Color(hex: 0x0B0E17)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle().strokeBorder(accent.opacity(0.6), lineWidth: 1.5)
                )
                .frame(width: coreDiameter, height: coreDiameter)

            powerGlyph
                .frame(width: glyphDiameter, height: glyphDiameter)
        }
    }

    /// The power symbol: a ring broken at the top with a stem through the gap.
    /// Drawn rather than taken from SF Symbols so it is the same mark as
    /// Android's, which is also drawn.
    private var powerGlyph: some View {
        Canvas { context, size in
            let stroke: CGFloat = 3
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.34

            var ring = Path()
            ring.addArc(
                center: c,
                radius: r,
                startAngle: .degrees(-60),
                endAngle: .degrees(220),
                clockwise: false
            )
            context.stroke(
                ring,
                with: .color(accentBright),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round)
            )

            var stem = Path()
            stem.move(to: CGPoint(x: c.x, y: c.y - r * 1.2))
            stem.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.1))
            context.stroke(
                stem,
                with: .color(accentBright),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round)
            )
        }
    }

    // MARK: - Clocks
    //
    // Periods are Android's, in seconds: spin 1200ms linear, pulse 1300ms and
    // breathe 1900ms, both reversing.

    private func spin(at t: TimeInterval) -> Double {
        (t.truncatingRemainder(dividingBy: 1.2) / 1.2) * 360
    }

    private func glowAlpha(at t: TimeInterval) -> Double {
        switch phase {
        case .off: return 0.5
        case .connecting: return oscillate(t, period: 1.3, from: 0.45, to: 0.95)
        case .on: return oscillate(t, period: 1.9, from: 0.62, to: 1.0)
        }
    }

    /// A reversing ramp eased like Compose's FastOutSlowInEasing. Smoothstep is
    /// not that curve to the decimal, but it is the same shape — symmetric,
    /// zero slope at both ends — and the difference is not visible on a glow.
    private func oscillate(_ t: TimeInterval, period: Double, from: Double, to: Double) -> Double {
        let x = t.truncatingRemainder(dividingBy: period * 2) / period
        let triangle = x <= 1 ? x : 2 - x
        let eased = triangle * triangle * (3 - 2 * triangle)
        return from + (to - from) * eased
    }

    // MARK: - Helpers

    private var accent: Color { phase.accent() }
    private var accentBright: Color { phase.accent(bright: true) }

    private func square(around c: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
    }

    private var accessibilityLabel: String {
        switch phase {
        case .off: return "Connect"
        case .connecting: return "Connecting, tap to cancel"
        case .on: return "Connected, tap to disconnect"
        }
    }
}
