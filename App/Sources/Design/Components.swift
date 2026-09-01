//
//  Components.swift — the shared glyphs and buttons, ported from Android's
//  `ui/components/Icons.kt` and `ui/components/Buttons.kt`.
//
//  The glyphs are drawn rather than taken from SF Symbols. SF Symbols would be
//  less code, but Android draws these by hand and an SF shield is a visibly
//  different shape from that one — the point of this file is that the two
//  clients show the same mark.
//
import SwiftUI

// MARK: - Glyphs

/// The Avangard shield outline. A `Shape` rather than a drawing function
/// because two callers need it in different treatments — stroked in the nav,
/// filled on the splash — and a second copy of these curves would drift.
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.55))
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.96),
            control1: CGPoint(x: w * 0.86, y: h * 0.80),
            control2: CGPoint(x: w * 0.70, y: h * 0.92)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.14, y: h * 0.55),
            control1: CGPoint(x: w * 0.30, y: h * 0.92),
            control2: CGPoint(x: w * 0.14, y: h * 0.80)
        )
        p.addLine(to: CGPoint(x: w * 0.14, y: h * 0.24))
        p.closeSubpath()
        return p
    }
}

struct ShieldIcon: View {
    var tint: Color
    var size: CGFloat = 22

    var body: some View {
        ShieldShape()
            .stroke(tint, style: StrokeStyle(lineWidth: 1.9, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

struct PersonIcon: View {
    var tint: Color
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let style = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)

            let headRadius = w * 0.16
            let headCenter = CGPoint(x: w * 0.5, y: h * 0.32)
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: headCenter.x - headRadius,
                    y: headCenter.y - headRadius,
                    width: headRadius * 2,
                    height: headRadius * 2
                )),
                with: .color(tint),
                style: style
            )

            var shoulders = Path()
            shoulders.move(to: CGPoint(x: w * 0.22, y: h * 0.86))
            shoulders.addCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.86),
                control1: CGPoint(x: w * 0.22, y: h * 0.60),
                control2: CGPoint(x: w * 0.78, y: h * 0.60)
            )
            context.stroke(shoulders, with: .color(tint), style: style)
        }
        .frame(width: size, height: size)
    }
}

struct ChevronDownIcon: View {
    var tint: Color
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            var p = Path()
            p.move(to: CGPoint(x: w * 0.28, y: h * 0.40))
            p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.62))
            p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.40))
            context.stroke(p, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Buttons

/// Filled indigo-gradient primary action.
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var loading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: enabled
                        ? [Theme.indigoBright, Theme.indigo]
                        : [Theme.indigo.opacity(0.35), Theme.indigo.opacity(0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled || loading)
    }
}

/// Outlined glass secondary action. `danger` tints border and label rose.
struct GlassButton: View {
    let title: String
    var danger: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(danger ? Theme.rose : Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Theme.glassBottom,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(danger ? Theme.rose.opacity(0.45) : Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
