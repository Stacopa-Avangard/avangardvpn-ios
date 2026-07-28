//
//  QuotaMeter.swift — bandwidth used against the monthly limit.
//
//  A single ratio against a limit is a meter, not a chart: no axes, no legend,
//  one value. The number leads and the bar supports it.
//
//  The fill carries severity and the unfilled track is a lighter step of the
//  SAME ramp, so the state reads across the whole bar rather than only in the
//  filled part. Severity is never colour-alone — every state ships an icon and
//  a worded label beside it.
//
import SwiftUI

struct QuotaMeter: View {
    let usage: UsageSummary

    private enum Severity {
        case normal, approaching, over, suspended

        var tint: Color {
            switch self {
            case .normal: return Theme.brand
            case .approaching: return Theme.statusWarning
            case .over, .suspended: return Theme.statusCritical
            }
        }

        var icon: String {
            switch self {
            case .normal: return "checkmark.circle.fill"
            case .approaching: return "exclamationmark.triangle.fill"
            case .over: return "exclamationmark.octagon.fill"
            case .suspended: return "pause.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .normal: return "Within quota"
            case .approaching: return "Approaching quota"
            case .over: return "Over quota"
            case .suspended: return "Suspended — quota exceeded"
            }
        }
    }

    private var severity: Severity {
        if usage.suspended { return .suspended }
        guard !usage.unlimited else { return .normal }
        if usage.fraction >= 1 { return .over }
        if usage.fraction >= 0.8 { return .approaching }
        return .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if usage.unlimited {
                Text("No monthly limit on this account.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                track
                footer
            }

            statusLine
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Data used")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            // The value leads; proportional figures, not tabular — this is a
            // standalone number, not a column that has to line up.
            Text(verbatim: ByteFormat.string(usage.usedBytes))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.inkPrimary)
        }
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Unfilled track: a lighter step of the fill's own ramp.
                Capsule()
                    .fill(severity.tint.opacity(0.22))
                Capsule()
                    .fill(severity.tint)
                    .frame(width: max(0, min(1, usage.fraction)) * geo.size.width)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Data used")
        .accessibilityValue(
            "\(ByteFormat.string(usage.usedBytes)) of \(ByteFormat.string(usage.quotaBytes)). \(severity.label)."
        )
    }

    private var footer: some View {
        HStack {
            Text(verbatim: "\(Int((usage.fraction * 100).rounded()))% of \(ByteFormat.string(usage.quotaBytes))")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(verbatim: usage.period)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private var statusLine: some View {
        Label {
            Text(severity.label)
                .font(.caption)
                // Text keeps ink tokens; the icon beside it carries the state.
                .foregroundStyle(Theme.inkSecondary)
        } icon: {
            Image(systemName: severity.icon)
                .foregroundStyle(severity.tint)
        }
        .labelStyle(.titleAndIcon)
    }
}

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .binary
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(0, bytes))
    }
}
