//
//  LoginView.swift — email entry + "check your inbox" waiting state.
//
//  Deliberately minimal: the full dark/glass design lands in P4. What matters
//  here is that the two states of the poll flow are honest about what is going
//  on — in particular, "email sent" must not imply the address is registered,
//  because the backend never tells us.
//
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var email = ""
    @State private var isSubmitting = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.brandPrimary)

                Text("Avangard VPN")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                if case let .awaitingLink(pendingEmail) = auth.state {
                    waitingForLink(email: pendingEmail)
                } else {
                    emailEntry
                }

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .padding()
        }
    }

    private var emailEntry: some View {
        VStack(spacing: 16) {
            Text("Sign in with a link sent to your email.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // `prompt:` rather than the title argument — the plain title
            // renders in the accent colour against this dark field, which reads
            // as filled-in text rather than a placeholder.
            // Hand-rolled placeholder. SwiftUI ignores the colour set on a
            // `prompt:` Text here — it renders in the accent colour against
            // this dark field, which reads as already-filled-in text.
            ZStack(alignment: .leading) {
                if email.isEmpty {
                    // `verbatim:` is load-bearing. A plain `Text("…")` literal
                    // gets parsed as Markdown, and an email address matches the
                    // autolink rule — SwiftUI then renders it as a tinted link
                    // and ignores any colour set on it.
                    Text(verbatim: "nama@email.com")
                        .foregroundColor(.gray)
                }
                TextField("", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($emailFocused)
                    .foregroundStyle(.white)
            }
            .padding()
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .tint(Color.brandPrimary)

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send sign-in link").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .disabled(isSubmitting || email.isEmpty)
            .opacity(isSubmitting || email.isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, 32)
    }

    private func waitingForLink(email: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().tint(.white)

            Text("Check your email")
                .font(.headline)
                .foregroundStyle(.white)

            // Phrased as "if the address is registered" on purpose — a 204 from
            // /auth/request-link does not confirm the account exists.
            Text(verbatim: "If \(email) is registered, a sign-in link is on its way. Open it on any device — this app will sign in automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Use a different email") {
                auth.cancelPendingLogin()
            }
            .font(.footnote)
            .foregroundStyle(Color.brandPrimary)
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    private func submit() async {
        emailFocused = false
        isSubmitting = true
        await auth.requestLink(email: email)
        isSubmitting = false
    }
}

extension Color {
    /// Brand primary — the same `#0D6EFD` the portal and Android app use.
    static let brandPrimary = Color(red: 0x0D / 255, green: 0x6E / 255, blue: 0xFD / 255)
}
