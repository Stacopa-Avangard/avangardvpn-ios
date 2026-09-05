//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  QuotaMeter.swift — bandwidth used against the monthly limit.
//
//  Ported from Android's `QuotaBar`: a gradient fill on a faint track, the used
//  figure and the cap underneath in monospace so the two line up, and a rose
//  line when the account is suspended.
//
//  The fill goes amber once the account is near or over its limit, which is the
//  same threshold the Home banner uses (80%). Severity is never colour-alone —
//  the figures under the bar and the accessibility value both say it in words.
//
import SwiftUI

struct QuotaMeter: View {
    let usage: UsageSummary?

    private var nearLimit: Bool {
        guard let usage else { return false }
        return usage.suspended || usage.fraction >= 0.8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHead(title: "Data this month", aside: "resets monthly")
                .padding(.bottom, 12)

            if let usage {
                if usage.unlimited {
                    Text("Unlimited")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                } else {
                    bar(usage)
                    figures(usage)
                    if usage.suspended {
                        Text("Paused — monthly limit reached.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.rose)
                            .padding(.top, 6)
                    }
                }
            } else {
                Text(verbatim: "—")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func bar(_ usage: UsageSummary) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: nearLimit
                                ? [Theme.amber, Theme.amberBright]
                                : [Theme.indigo, Theme.indigoBright],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: min(1, max(0, usage.fraction)) * geo.size.width)
            }
        }
        .frame(height: 9)
        .accessibilityElement()
        .accessibilityLabel("Data used this month")
        .accessibilityValue(accessibilityValue(usage))
    }

    private func figures(_ usage: UsageSummary) -> some View {
        HStack {
            Text(verbatim: "\(ByteFormat.string(usage.usedBytes)) used")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.text)
            Spacer()
            Text(verbatim: ByteFormat.string(usage.quotaBytes))
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 10)
    }

    private func accessibilityValue(_ usage: UsageSummary) -> String {
        let base = "\(ByteFormat.string(usage.usedBytes)) of \(ByteFormat.string(usage.quotaBytes))"
        if usage.suspended { return "\(base). Suspended, monthly limit reached." }
        if usage.fraction >= 1 { return "\(base). Over quota." }
        if usage.fraction >= 0.8 { return "\(base). Approaching quota." }
        return "\(base). Within quota."
    }
}

/// A card's title with a quiet aside on the right — Android's `CardHead`.
struct CardHead: View {
    let title: String
    let aside: String

    var body: some View {
        HStack(alignment: .bottom) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Text(aside)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
    }
}
