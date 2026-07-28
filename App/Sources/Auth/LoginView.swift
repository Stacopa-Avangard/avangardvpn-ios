//
//  LoginView.swift — email entry + "check your inbox" waiting state.
//
//  The two states of the poll flow have to be honest about what is going on —
//  in particular, "email sent" must not imply the address is registered,
//  because the backend deliberately never tells us.
//
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var email = ""
    @State private var isSubmitting = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.brand)

                Text("Avangard VPN")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.inkPrimary)

                if case let .awaitingLink(pendingEmail) = auth.state {
                    waitingForLink(email: pendingEmail)
                } else {
                    emailEntry
                }

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.statusCritical)
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
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

            ZStack(alignment: .leading) {
                if email.isEmpty {
                    // `verbatim:` is load-bearing. A plain `Text("…")` literal
                    // gets parsed as Markdown, and an email address matches the
                    // autolink rule — SwiftUI then renders it as a tinted link
                    // and ignores any colour set on it.
                    Text(verbatim: "name@email.com")
                        .foregroundColor(Theme.inkMuted)
                }
                TextField("", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($emailFocused)
                    .foregroundStyle(Theme.inkPrimary)
            }
            .padding()
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .tint(Theme.brand)

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(Theme.inkPrimary)
                    } else {
                        Text("Send sign-in link").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Theme.inkPrimary)
            .disabled(isSubmitting || email.isEmpty)
            .opacity(isSubmitting || email.isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, 32)
    }

    private func waitingForLink(email: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().tint(Theme.inkPrimary)

            Text("Check your email")
                .font(.headline)
                .foregroundStyle(Theme.inkPrimary)

            // Phrased as "if the address is registered" on purpose — a 204 from
            // /auth/request-link does not confirm the account exists.
            Text(verbatim: "If \(email) is registered, a sign-in link is on its way. Open it on any device — this app will sign in automatically.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

            Button("Use a different email") {
                auth.cancelPendingLogin()
            }
            .font(.footnote)
            .foregroundStyle(Theme.brand)
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
