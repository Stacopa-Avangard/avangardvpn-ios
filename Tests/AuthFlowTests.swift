//
//  AuthFlowTests.swift — integration tests for the poll-login flow.
//
//  These talk to a REAL backend, run locally:
//
//      cd wireguard-dashboard/backend && pnpm dev
//
//  and are driven by `Scripts/run-auth-tests.sh`, which does the parts a test
//  inside the Simulator cannot: it reads the magic-link token out of the
//  backend's stdout (dev logs it instead of emailing) and clicks the link.
//  The test then claims the session exactly as the app would.
//
//  Without `AVANGARD_API_BASE` set, every test here skips — so CI's unsigned
//  compile-check stays green with no backend around.
//
import XCTest
@testable import AvangardVPN

final class AuthFlowTests: XCTestCase {

    private var isConfigured: Bool {
        ProcessInfo.processInfo.environment["AVANGARD_API_BASE"] != nil
    }

    override func setUp() {
        super.setUp()
        TokenStore.clear()
    }

    override func tearDown() {
        TokenStore.clear()
        super.tearDown()
    }

    /// The app points at whatever `AVANGARD_API_BASE` says — the DEBUG-only
    /// override that makes local testing possible at all.
    func testBaseURLHonoursDebugOverride() throws {
        try XCTSkipUnless(isConfigured, "set AVANGARD_API_BASE to run integration tests")
        let expected = ProcessInfo.processInfo.environment["AVANGARD_API_BASE"]!
        XCTAssertEqual(AppConfig.baseURL.absoluteString, expected)
    }

    /// An unknown login-session id must read as `expired`, never `pending` —
    /// that is what stops someone probing for valid ids.
    func testPollWithUnknownSessionIsExpired() async throws {
        try XCTSkipUnless(isConfigured, "set AVANGARD_API_BASE to run integration tests")
        let response = try await APIClient.shared.poll(loginSessionId: String(repeating: "z", count: 43))
        XCTAssertEqual(response.status, .expired)
    }

    /// `/auth/request-link` answers 204 for an address that does not exist, and
    /// the session it opens polls as `pending`. Both halves matter: the 204 is
    /// the anti-enumeration behaviour, and `pending` proves the login session
    /// was created even for an unknown email.
    func testRequestLinkForUnknownEmailStillOpensPendingSession() async throws {
        try XCTSkipUnless(isConfigured, "set AVANGARD_API_BASE to run integration tests")
        let sessionId = Self.newLoginSessionId()

        try await APIClient.shared.requestLink(
            email: "definitely-not-registered@avangard.local",
            loginSessionId: sessionId
        )

        let response = try await APIClient.shared.poll(loginSessionId: sessionId)
        XCTAssertEqual(response.status, .pending)
    }

    /// The whole point: claim a session whose link the harness already clicked,
    /// persist it, and use the resulting access token on a real authenticated
    /// endpoint. Covers URL building, JSON decoding, Keychain persistence, and
    /// the bearer header in one pass.
    func testClaimVerifiedSessionAndCallAuthenticatedEndpoint() async throws {
        try XCTSkipUnless(isConfigured, "set AVANGARD_API_BASE to run integration tests")
        guard let sessionId = ProcessInfo.processInfo.environment["AVANGARD_VERIFIED_SESSION_ID"] else {
            throw XCTSkip("no pre-verified session supplied; run via Scripts/run-auth-tests.sh")
        }

        let claim = try await APIClient.shared.poll(loginSessionId: sessionId)
        XCTAssertEqual(claim.status, .verified)

        let access = try XCTUnwrap(claim.access)
        let refresh = try XCTUnwrap(claim.refresh)
        let user = try XCTUnwrap(claim.user)

        try TokenStore.save(SessionResponse(access: access, refresh: refresh, user: user))
        XCTAssertTrue(TokenStore.hasSession)
        XCTAssertEqual(TokenStore.access, access)
        XCTAssertEqual(TokenStore.user, user)

        // Authenticated call with the token we just claimed.
        let me = try await APIClient.shared.me()
        XCTAssertEqual(me.id, user.id)
        XCTAssertEqual(me.email, user.email)

        // Claiming is single-use — a second poll must not hand out tokens again.
        let second = try await APIClient.shared.poll(loginSessionId: sessionId)
        XCTAssertEqual(second.status, .expired)
    }

    /// Rotation: refreshing must mint a NEW refresh token and leave the stored
    /// session usable. The old refresh dies server-side the moment this returns.
    func testRefreshRotatesAndPersists() async throws {
        try XCTSkipUnless(isConfigured, "set AVANGARD_API_BASE to run integration tests")
        guard let sessionId = ProcessInfo.processInfo.environment["AVANGARD_VERIFIED_SESSION_ID_2"] else {
            throw XCTSkip("no second pre-verified session supplied")
        }

        let claim = try await APIClient.shared.poll(loginSessionId: sessionId)
        try XCTSkipUnless(claim.status == .verified, "session was not verified")
        try TokenStore.save(SessionResponse(
            access: try XCTUnwrap(claim.access),
            refresh: try XCTUnwrap(claim.refresh),
            user: try XCTUnwrap(claim.user)
        ))
        let originalRefresh = try XCTUnwrap(TokenStore.refresh)

        let rotated = try await APIClient.shared.refreshSession()

        XCTAssertNotEqual(rotated.refresh, originalRefresh, "refresh token must rotate")
        XCTAssertEqual(TokenStore.refresh, rotated.refresh, "new refresh must be persisted")

        // The rotated access token still works.
        let me = try await APIClient.shared.me()
        XCTAssertEqual(me.id, rotated.user.id)
    }

    /// Keychain round-trip, independent of the network.
    func testKeychainStoresAndClearsSession() throws {
        let user = AuthUser(id: "u1", email: "a@b.test", name: "Test", role: "user")
        try TokenStore.save(SessionResponse(access: "acc", refresh: "ref", user: user))

        XCTAssertEqual(TokenStore.access, "acc")
        XCTAssertEqual(TokenStore.refresh, "ref")
        XCTAssertEqual(TokenStore.user, user)
        XCTAssertTrue(TokenStore.hasSession)

        TokenStore.clear()
        XCTAssertNil(TokenStore.access)
        XCTAssertNil(TokenStore.refresh)
        XCTAssertFalse(TokenStore.hasSession)
    }

    /// Same construction the app uses — 43 chars is the backend's floor.
    private static func newLoginSessionId() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
