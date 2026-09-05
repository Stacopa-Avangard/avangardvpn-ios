//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  LoginView.swift — email entry + "check your inbox" waiting state.
//
//  Ported to match Android's LoginScreen.kt: the shield mark, the email field,
//  the primary action, and — under the waiting state — a collapsed "Have a
//  sign-in code?" affordance for the App Store reviewer.
//
//  The two states of the poll flow have to be honest about what is going on —
//  in particular, "email sent" must not imply the address is registered,
//  because the backend deliberately never tells us.
//
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL

    @State private var email = ""
    @State private var isSubmitting = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ShieldMark()

            Text("AvangardVPN")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.top, 18)

            if case let .awaitingLink(pendingEmail) = auth.state {
                WaitingForLink(email: pendingEmail)
                    .padding(.top, 26)
            } else {
                emailEntry
                    .padding(.top, 26)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Email entry

    private var emailEntry: some View {
        VStack(spacing: 0) {
            Text("Sign in with a link sent to your email.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)

            ZStack(alignment: .leading) {
                if email.isEmpty {
                    // `verbatim:` is load-bearing. A plain `Text("…")` literal
                    // gets parsed as Markdown, and an email address matches the
                    // autolink rule — SwiftUI then renders it as a tinted link
                    // and ignores any colour set on it.
                    Text(verbatim: "name@email.com")
                        .foregroundStyle(Theme.faint)
                }
                TextField("", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.done)
                    .focused($emailFocused)
                    .foregroundStyle(Theme.text)
                    .onSubmit { Task { await submit() } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(emailFocused ? Theme.indigo : Theme.stroke, lineWidth: 1)
            )
            .tint(Theme.indigoBright)

            PrimaryButton(
                title: "Send magic link",
                enabled: !email.trimmingCharacters(in: .whitespaces).isEmpty,
                loading: isSubmitting
            ) {
                Task { await submit() }
            }
            .padding(.top, 16)

            if let message = auth.errorMessage {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.rose)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }

            Text("Invite-only")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .padding(.top, 18)

            // The first data we ever collect is the email typed above, so the
            // policy has to be reachable from here — not only from Account,
            // which needs an account to reach.
            HStack(spacing: 14) {
                legalLink("Privacy Policy", url: LegalUrls.privacy)
                legalLink("Terms", url: LegalUrls.terms)
            }
            .padding(.top, 14)
        }
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

    private func submit() async {
        emailFocused = false
        isSubmitting = true
        await auth.requestLink(email: email)
        isSubmitting = false
    }
}

// MARK: - Waiting state

private struct WaitingForLink: View {
    let email: String

    @EnvironmentObject private var auth: AuthStore

    /// Collapsed by default: this is for the App Store reviewer, who is told
    /// where to find it, not a second way in that everyone is nudged toward.
    @State private var showCode = false
    @State private var code = ""

    var body: some View {
        VStack(spacing: 0) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(Theme.indigoBright)

            Text("Check your email")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.top, 18)

            // Phrased as "if the address is registered" on purpose — a 204 from
            // /auth/request-link does not confirm the account exists.
            Text("If this address is registered, a link is on its way to")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Text(verbatim: email)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            Text("Open it on any device — this app signs in automatically.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Button("Use a different email") {
                auth.cancelPendingLogin()
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.indigoBright)
            .buttonStyle(.plain)
            .padding(.top, 20)

            if showCode {
                codeEntry.padding(.top, 10)
            } else {
                Button("Have a sign-in code?") {
                    showCode = true
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if code.isEmpty {
                    Text(verbatim: "Sign-in code")
                        .foregroundStyle(Theme.faint)
                }
                TextField("", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .foregroundStyle(Theme.text)
                    .onSubmit { Task { await auth.signInWithCode(code) } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(auth.errorMessage == nil ? Theme.stroke : Theme.rose, lineWidth: 1)
            )
            .tint(Theme.indigoBright)
            .disabled(auth.isCheckingCode)

            if let message = auth.errorMessage {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.rose)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }

            PrimaryButton(
                title: "Sign in with code",
                enabled: !code.trimmingCharacters(in: .whitespaces).isEmpty,
                loading: auth.isCheckingCode
            ) {
                Task { await auth.signInWithCode(code) }
            }
            .padding(.top, 10)
        }
    }
}

// MARK: - Brand mark

/// The app-icon logo: the white Avangard shield on the deep-indigo → brand-blue
/// gradient. The one place `Theme.markEnd` is used.
private struct ShieldMark: View {
    var body: some View {
        ShieldShape()
            .fill(.white)
            .frame(width: 32, height: 32)
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [Theme.markStart, Theme.markEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
    }
}
