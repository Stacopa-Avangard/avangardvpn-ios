//
//  BottomNav.swift — the floating tab bar, ported from Android's RootScreen.kt.
//
//  Not a `TabView`. UIKit's tab bar is a docked opaque strip, and the whole
//  point of this control on Android is that it floats over the ambient wash
//  with a glass fill and a pill that slides between the two items. A styled
//  TabView cannot do either, so the shell composes the screen and this bar in
//  a ZStack instead.
//
//  Screens are responsible for keeping their last row clear of it — they pad
//  by `Theme.bottomNavClearance`, exactly as the Android screens do.
//
import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
    case home = 0
    case account = 1

    var title: String {
        switch self {
        case .home: return "Home"
        case .account: return "Account"
        }
    }
}

struct BottomNav: View {
    @Binding var selection: AppTab

    private let barHeight: CGFloat = 66
    private let innerPadding: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let itemWidth = (geo.size.width - innerPadding * 2) / CGFloat(AppTab.allCases.count)

            ZStack(alignment: .leading) {
                // The sliding indigo pill, drawn under the items.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.indigo.opacity(0.34), Theme.indigo.opacity(0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.indigo.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: itemWidth)
                    .offset(x: itemWidth * CGFloat(selection.rawValue))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)

                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        navItem(tab)
                            .frame(width: itemWidth)
                    }
                }
            }
            .padding(innerPadding)
        }
        .frame(height: barHeight)
        /*
          A backdrop under the glass, which Android does not need and iOS does.
          Both clients scroll content *behind* this bar. On Android the screens
          are Columns that end at the clearance, so what passes underneath is
          empty ground; on iOS the Account tab is a ScrollView whose last cards
          slide right under it, and a 7.5%-white gradient over live text is not
          a surface — the label reads through the bar and collides with "Home"
          and "Account". The ground at 78% keeps the glass reading as glass
          while giving the labels something opaque to sit on.
        */
        .background(
            Theme.ground.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .glass(cornerRadius: 22)
    }

    private func navItem(_ tab: AppTab) -> some View {
        let selected = selection == tab
        let tint = selected ? Theme.indigoBright : Theme.muted

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                switch tab {
                case .home: ShieldIcon(tint: tint, size: 21)
                case .account: PersonIcon(tint: tint, size: 21)
                }
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
