//
//  SPDX-License-Identifier: GPL-3.0-only
//  Copyright © 2026 PT Stacopa Avangard Raya
//
//  AuthStore.swift — sign-in state machine (device/poll flow).
//
//  Why polling instead of a deep link: the Android app learned the hard way
//  that handing the magic link back to the app is fragile (Gmail strips custom
//  schemes; App Link verification is unreliable on some OEM builds). The poll
//  flow sidesteps the handoff entirely — the app invents a login-session id,
//  sends it with the email request, and then just asks the backend whether the
//  link has been clicked *anywhere*. The browser that opens the link never
//  needs to know an app exists.
//
import Foundation
import Security

@MainActor
final class AuthStore: ObservableObject {
    enum State: Equatable {
        /// Checking the Keychain for an existing session on launch.
        case restoring
        case signedOut
        /// Email sent; waiting for the user to click the link in their inbox.
        case awaitingLink(email: String)
        case signedIn(AuthUser)
    }

    @Published private(set) var state: State = .restoring
    @Published var errorMessage: String?

    private var pollTask: Task<Void, Never>?

    /// The login session the current `.awaitingLink` is polling. Signing in by
    /// code has to reuse it — the code verifies THAT session, and the poll
    /// already running is what claims the tokens.
    private var pendingLoginSessionId: String?

    /// Set while a code is being checked, so the button can show a spinner
    /// without the email form's `isSubmitting` doing double duty.
    @Published private(set) var isCheckingCode = false

    // MARK: - Lifecycle

    /// Restore a session at launch. A stored refresh token is not proof of a
    /// live session (it may have been revoked, or the account disabled), so we
    /// verify it against `/api/me` before showing a signed-in UI.
    func restore() async {
        #if DEBUG
        // Dev affordance, compiled out of Release alongside AVANGARD_API_BASE:
        // claim a login session prepared outside the app, so the signed-in UI
        // can be launched without typing an address and opening a mail client.
        // See Scripts/run-dev-session.sh.
        if !TokenStore.hasSession,
           let devSession = AppConfig.environment("AVANGARD_DEV_SESSION_ID") {
            await claimDevSession(devSession)
            if case .signedIn = state { return }
        }
        #endif

        guard TokenStore.hasSession else {
            state = .signedOut
            return
        }
        do {
            let user = try await APIClient.shared.me()
            state = .signedIn(user)
        } catch APIError.notAuthenticated {
            TokenStore.clear()
            state = .signedOut
        } catch {
            // Offline at launch: the session is probably still valid, so trust
            // the cached user rather than signing them out over a dropped
            // network. The next authenticated call will correct us if not.
            if let cached = TokenStore.user {
                state = .signedIn(cached)
            } else {
                state = .signedOut
            }
        }
    }

    // MARK: - Sign in

    func requestLink(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }

        errorMessage = nil
        let loginSessionId = Self.newLoginSessionId()

        do {
            try await APIClient.shared.requestLink(email: trimmed, loginSessionId: loginSessionId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't send the sign-in link."
            return
        }

        // A 204 says nothing about whether the address is registered — the
        // backend answers identically either way to prevent account probing.
        // So we always move to "check your email" and let the poll time out.
        state = .awaitingLink(email: trimmed)
        pendingLoginSessionId = loginSessionId
        startPolling(loginSessionId: loginSessionId)
    }

    /// User backed out of the "check your email" screen. The login session is
    /// left to expire server-side on its own; there is no cancel endpoint.
    func cancelPendingLogin() {
        pollTask?.cancel()
        pollTask = nil
        pendingLoginSessionId = nil
        errorMessage = nil
        state = .signedOut
    }

    /// Sign in with a code instead of waiting for the emailed link.
    ///
    /// Only reachable from the "check your email" state, because the code
    /// verifies the login session that state is already polling. On success
    /// the backend has marked that session verified and this claims it
    /// immediately rather than waiting out the poll interval — the reviewer
    /// should not sit watching a spinner for three seconds after a correct
    /// code.
    func signInWithCode(_ code: String) async {
        guard case let .awaitingLink(email) = state, let sessionId = pendingLoginSessionId else {
            return
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil
        isCheckingCode = true
        defer { isCheckingCode = false }

        do {
            try await APIClient.shared.demoLogin(
                email: email, code: trimmed, loginSessionId: sessionId
            )
        } catch {
            // Deliberately one message for every failure. The backend refuses
            // to distinguish a wrong code from an unknown address from a
            // deployment with no demo account, and neither should we.
            errorMessage = "That code was not accepted."
            return
        }

        guard
            let response = try? await APIClient.shared.poll(loginSessionId: sessionId),
            response.status == .verified
        else {
            // The code was accepted but the claim did not land. The poll is
            // still running and will pick it up; say nothing rather than
            // showing an error over a sign-in that is about to succeed.
            return
        }

        pollTask?.cancel()
        pollTask = nil
        completeSignIn(response)
    }

    func signOut() async {
        pollTask?.cancel()
        pollTask = nil
        await APIClient.shared.logout()
        TokenStore.clear()
        state = .signedOut
    }

    /// Delete the account and sign out. Required by App Store Review 5.1.1(v):
    /// an app that lets people create an account must let them delete it from
    /// inside the app, not only by writing to support.
    ///
    /// Returns the message to show on failure, nil on success. The caller must
    /// take the tunnel down first — see `APIClient.deleteAccount`.
    func deleteAccount() async -> String? {
        do {
            try await APIClient.shared.deleteAccount()
        } catch APIError.http(status: 404, code: _) {
            // Already gone; that is the outcome that was asked for.
        } catch let APIError.http(status: 409, code: code) where code == "last_admin" {
            return "This is the last administrator account, so it cannot be deleted."
        } catch {
            return (error as? LocalizedError)?.errorDescription
                ?? "Couldn't delete your account. Please try again."
        }

        pollTask?.cancel()
        pollTask = nil
        pendingLoginSessionId = nil
        TokenStore.clear()
        state = .signedOut
        return nil
    }

    // MARK: - Polling

    private func startPolling(loginSessionId: String) {
        pollTask?.cancel()

        let deadline = Date().addingTimeInterval(
            Double(AppConfig.pollTimeout.components.seconds)
        )

        pollTask = Task { [weak self] in
            while !Task.isCancelled && Date() < deadline {
                do {
                    try await Task.sleep(for: AppConfig.pollInterval)
                } catch {
                    return // cancelled
                }

                guard let self, !Task.isCancelled else { return }

                do {
                    let response = try await APIClient.shared.poll(loginSessionId: loginSessionId)
                    switch response.status {
                    case .pending:
                        continue
                    case .verified:
                        self.completeSignIn(response)
                        return
                    case .expired:
                        self.failPending("That sign-in link expired. Please try again.")
                        return
                    }
                } catch {
                    // A single failed poll is usually a blip (backgrounded app,
                    // flaky network). Keep polling until the deadline rather
                    // than dropping the user out of the flow.
                    continue
                }
            }

            if !Task.isCancelled {
                self?.failPending("Sign-in timed out. Request a new link.")
            }
        }
    }

    private func completeSignIn(_ response: PollResponse) {
        guard let access = response.access,
              let refresh = response.refresh,
              let user = response.user
        else {
            failPending("The server's response was incomplete. Please try again.")
            return
        }

        do {
            try TokenStore.save(SessionResponse(access: access, refresh: refresh, user: user))
        } catch {
            failPending("Couldn't save your session to the Keychain.")
            return
        }
        pendingLoginSessionId = nil
        errorMessage = nil
        state = .signedIn(user)
    }

    private func failPending(_ message: String) {
        pendingLoginSessionId = nil
        errorMessage = message
        state = .signedOut
    }

    #if DEBUG
    /// Claim a login session that a dev script already verified. Failure is
    /// silent — the app just falls through to the normal sign-in screen.
    private func claimDevSession(_ sessionId: String) async {
        guard let response = try? await APIClient.shared.poll(loginSessionId: sessionId),
              response.status == .verified
        else { return }
        completeSignIn(response)
    }
    #endif

    /// 32 random bytes as unpadded base64url — 43 characters, which is exactly
    /// the backend's `min(43)` floor (it enforces ≥256 bits of entropy because
    /// this id is the bearer secret for claiming the session's tokens).
    private static func newLoginSessionId() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
