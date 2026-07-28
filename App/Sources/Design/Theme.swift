//
//  Theme.swift — the app's visual tokens.
//
//  One place for colour and metrics so screens stay consistent as they grow.
//  The app is dark-only (matching the Android client), so these are picked
//  against a black surface rather than flipped from a light set.
//
import SwiftUI

enum Theme {
    // MARK: - Surfaces

    /// True black — the app is OLED-friendly and the glass cards read against it.
    static let background = Color.black
    /// Card fill. Kept as an opacity over the background so stacked surfaces
    /// stay related instead of drifting into arbitrary greys.
    static let surface = Color.white.opacity(0.06)
    static let surfaceRaised = Color.white.opacity(0.12)
    static let separator = Color.white.opacity(0.10)

    // MARK: - Ink
    //
    // Text always wears these, never a data colour — a coloured mark sitting
    // beside a label is what carries meaning.

    static let inkPrimary = Color.white
    static let inkSecondary = Color.white.opacity(0.62)
    static let inkMuted = Color.white.opacity(0.40)

    // MARK: - Brand

    /// `#0D6EFD` — the same primary the portal and Android client use.
    static let brand = Color(red: 0x0D / 255, green: 0x6E / 255, blue: 0xFD / 255)

    // MARK: - Status
    //
    // Reserved for state, never reused as a decorative accent. Each one is
    // always shipped with an icon AND a label so the colour never carries the
    // meaning on its own. All clear 3:1 against the dark surface.

    static let statusGood = Color(red: 0x0C / 255, green: 0xA3 / 255, blue: 0x0C / 255)
    static let statusWarning = Color(red: 0xFA / 255, green: 0xB2 / 255, blue: 0x19 / 255)
    static let statusCritical = Color(red: 0xD0 / 255, green: 0x3B / 255, blue: 0x3B / 255)

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let stackSpacing: CGFloat = 20
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
    }
}

/// Section heading above a group of cards.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.inkPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Standard screen chrome: black background edge-to-edge, dark nav bar.
    func screenBackground() -> some View {
        self
            .background(Theme.background.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
