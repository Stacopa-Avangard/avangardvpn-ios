//
//  DataDisclosureView.swift — the in-app data declaration Guideline 5.4 requires.
//
//  5.4 (VPN Apps): "You must make a clear declaration of what user data will be
//  collected and how it will be used ON AN APP SCREEN prior to any user action
//  to purchase or otherwise use the service."
//
//  Two phrases in that sentence decide the shape of this file.
//
//  "on an app screen" — App Review has rejected VPN apps that answered this by
//  linking to their policy: "Mentioning this information in the app's Terms of
//  Service or Privacy Policy is not sufficient." The Legal links at the bottom
//  of LoginView satisfy 5.1.1(i), which is a different rule about reachability.
//  They do NOT satisfy this one. Do not delete this screen and lean on them.
//
//  "prior to any user action" — the first thing this app sends anywhere is the
//  email typed into LoginView, so the gate sits BEFORE that field, not before
//  Connect. The comment above LoginView's legal links makes the same point.
//
//  The required properties are ported from Android's VpnDisclosureDialog.kt,
//  which was written against Play's prominent-disclosure rules: inside the app,
//  before the capability is used, an affirmative action, and a decline that
//  actually declines. One deliberate difference — Android's dialog is scoped to
//  what the VpnService API itself collects, which is nothing, and sends the
//  account picture to the policy. Apple asks about the VPN *service*, so all
//  four account fields are named here rather than linked to.
//
//  ⚠️ Everything claimed below has to stay true in the backend. Where each claim
//  stands, checked 2026-09-04:
//
//    - Not in the database, and this one is enforced. The 90-day endpoint
//      history was stopped and its rows deleted; nothing calls
//      `peerEndpointsRepo.record()` any more, and
//      `backend/tests/no-client-ip-storage.test.ts` fails if a writer returns.
//    - Not in any log either — stated by the operator on 2026-09-04 for the
//      running deployment, which is not visible from this repo.
//
//  ⚠️ One artefact still contradicts that second line: `deploy/Caddyfile.example`
//  in the server repo writes a JSON access log to /var/log/caddy/access.log,
//  rotated at 30 days, and Caddy's JSON log carries `remote_ip`. It is an
//  example rather than the deployed config, so the droplet may well differ — but
//  while it sits there, the repo holds written evidence against the promise this
//  screen makes. Fix the example, or narrow this line. Do not leave both.
//
import SwiftUI

enum DataDisclosure {
    /// Bump when the wording materially widens, which re-prompts everyone who
    /// already agreed. Someone who accepted a narrower declaration has not
    /// accepted a wider one, and a silent widening is exactly what 5.4 is
    /// written to stop.
    static let version = 1

    static let storageKey = "dataDisclosureAcceptedVersion"
}

/// Shown in place of `LoginView` until the declaration is accepted.
struct DataDisclosureView: View {
    /// `@AppStorage` rather than a store: writing it re-renders `RootView`,
    /// which is the whole state machine this screen needs.
    @AppStorage(DataDisclosure.storageKey) private var acceptedVersion = 0

    @Environment(\.openURL) private var openURL

    /// Set by "Not now". A real decline has to lead somewhere other than back
    /// to the same prompt — re-asking in a loop is the failure mode Play names
    /// explicitly, and it reads just as badly to an App Review tester.
    @State private var declined = false

    /// Latched once the end of the declaration has been on screen.
    ///
    /// Pinning the buttons made them visible, which cost the property that the
    /// unpinned version had for free: you could not reach the button without
    /// passing the whole declaration. On an iPhone 12 the fold lands after the
    /// FIRST of the three "what we do not store" lines, so without this gate a
    /// user can accept having seen less than half of what they are accepting.
    /// It latches rather than tracking live — scrolling back up does not
    /// un-read what was read.
    @State private var readToEnd = false

    /// Measured, not assumed: the sentinel's position is only meaningful
    /// against the height of the viewport it is scrolling inside.
    @State private var viewportHeight: CGFloat = 0

    private static let scrollSpace = "disclosureScroll"

    var body: some View {
        Group {
            if declined {
                declinedState
            } else {
                declaration
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The declaration

    private var declaration: some View {
        // The declaration scrolls; the two actions do not.
        //
        // Verified on an iPhone 12 (1170×2532): with everything in one scroll
        // view the fold landed on the "we do not sell" line, so both buttons
        // sat off-screen with no scroll indicator to hint at them. A consent
        // screen whose consent button is invisible is a bad screen, and it is
        // weak against a reviewer who expects the affirmative action to be
        // present with the disclosure. Pinning costs one fold of scrolling and
        // removes the failure entirely.
        VStack(spacing: 0) {
            ScrollView(showsIndicators: true) {
                VStack(spacing: 0) {
                    DisclosureMark()
                        .padding(.top, 44)

                    Text("Before you sign in")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 18)

                    Text("AvangardVPN carries your internet traffic through an encrypted tunnel to our server, and it reaches the internet from there. Here is exactly what that costs you in data.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)

                    section("WHAT WE STORE") {
                        collected(
                            "Your email address",
                            "Only to send you the sign-in link. There are no passwords."
                        )
                        collected(
                            "Your device's public key",
                            "So the tunnel knows which device to route traffic to. The private key is generated on this iPhone and never leaves it."
                        )
                        collected(
                            "Total data used",
                            "To show how much of your plan's quota is left."
                        )
                        collected(
                            "Time of the last handshake",
                            "A housekeeping marker, so devices that have gone quiet can be released."
                        )
                    }

                    section("WHAT WE DO NOT STORE") {
                        excluded("Where you connect from. The server needs your address while the tunnel is up, but we keep no logs of it and it is never written to our database.")
                        excluded("Your browsing. No DNS lookups, no domains, no destination addresses.")
                        excluded("Anything from an ad network or an analytics SDK. There are none in this app.")
                    }

                    Text("We do not sell, share, or hand any of this to anyone else.")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)

                    HStack(spacing: 14) {
                        legalLink("Privacy Policy", url: LegalUrls.privacy)
                        legalLink("Terms", url: LegalUrls.terms)
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 40)

                    // One point at the very end of the declaration. When its
                    // bottom edge fits inside the viewport, everything above
                    // it has been on screen.
                    Color.clear
                        .frame(height: 1)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: DisclosureBottomKey.self,
                                    value: proxy.frame(in: .named(Self.scrollSpace)).maxY
                                )
                            }
                        )
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DisclosureViewportKey.self,
                        value: proxy.size.height
                    )
                }
            )
            .onPreferenceChange(DisclosureViewportKey.self) { viewportHeight = $0 }
            .onPreferenceChange(DisclosureBottomKey.self) { bottom in
                // `viewportHeight == 0` is the first layout pass, before the
                // height is known. Treating that as "fits" would unlock the
                // button before anything had been drawn.
                guard viewportHeight > 0, !readToEnd else { return }
                if bottom <= viewportHeight + 1 { readToEnd = true }
            }

            VStack(spacing: 10) {
                PrimaryButton(
                    title: readToEnd ? "I understand — continue" : "Scroll to read it all",
                    enabled: readToEnd
                ) {
                    acceptedVersion = DataDisclosure.version
                }
                GlassButton(title: "Not now") {
                    declined = true
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
            // The scroll runs under this, so fade the last few points of text
            // rather than letting a half-cut line sit against the buttons.
            .background(
                LinearGradient(
                    colors: [Theme.ground.opacity(0), Theme.ground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.top, -48)
                .allowsHitTesting(false)
            )
        }
    }

    // MARK: - The decline

    /// Honest rather than punitive: it names the one reason the app cannot go
    /// on, and offers the way back without nagging.
    private var declinedState: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("No problem")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)

            Text("Signing in sends your email address to our server, so there is no way to continue without agreeing to that first. Nothing has been sent.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            GlassButton(title: "Read it again") {
                declined = false
            }
            .padding(.top, 28)

            Spacer()
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.faint)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(
            Theme.glassBottom,
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .padding(.top, 22)
    }

    private func collected(_ title: String, _ why: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(why)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func excluded(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            // A dash, not a checkmark. A green tick next to "we do not store
            // your browsing" reads as a feature badge; this is a statement.
            Text(verbatim: "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.emerald)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legalLink(_ label: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text(label)
                .font(.system(size: 12))
                .underline()
                .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
    }
}

/// Distance from the top of the visible scroll area to the end of the
/// declaration. `min` because a preference tree can carry more than one value
/// during a layout pass and the nearest one is the honest answer.
private struct DisclosureBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

/// Height of the scroll viewport, which is what the value above is measured
/// against. Not a constant: it changes with Dynamic Type and on rotation.
private struct DisclosureViewportKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The sign-in shield at the size this screen wants. `LoginView.ShieldMark` is
/// private to that file and sized for a screen with far less below it.
private struct DisclosureMark: View {
    var body: some View {
        ShieldShape()
            .fill(.white)
            .frame(width: 26, height: 26)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(
                    colors: [Theme.markStart, Theme.markEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
    }
}
