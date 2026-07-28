//
//  APIClient.swift — the app's only network entry point.
//
//  An actor, for one specific reason: refresh-token rotation is single-use. If
//  two requests 401 at the same moment and both call `/auth/refresh`, the
//  second one presents an already-rotated token and the whole session dies.
//  `refreshInFlight` collapses concurrent refreshes into one shared task so
//  that cannot happen — the mirror of the Android app's interceptor.
//
import Foundation

enum APIError: Error, LocalizedError {
    case transport(Error)
    case http(status: Int, code: String?)
    case decoding(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .transport:
            return "Can't reach the server. Check your internet connection."
        case let .http(status, code):
            switch code {
            case "account_disabled": return "This account has been disabled."
            case "device_limit_reached": return "Device limit reached."
            case "unknown_region": return "Unknown region."
            default: return "The server rejected the request (HTTP \(status))."
            }
        case .decoding:
            return "Couldn't read the server's response."
        case .notAuthenticated:
            return "Your session expired. Please sign in again."
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var refreshInFlight: Task<SessionResponse, Error>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Unauthenticated auth flow

    /// Ask the backend to email a magic link. Always succeeds (204) whether or
    /// not the address is registered — the backend refuses to leak that, so the
    /// UI must not treat a success here as "this email exists".
    func requestLink(email: String, loginSessionId: String) async throws {
        var request = URLRequest(url: AppConfig.baseURL.appendingPathComponent("auth/request-link"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "email": email,
            "loginSessionId": loginSessionId,
        ])
        _ = try await perform(request)
    }

    /// Has the emailed link been clicked yet? Returns `.pending` until it is,
    /// then `.verified` once — the claim is single-use, so a second poll after
    /// success reports `.expired`.
    func poll(loginSessionId: String) async throws -> PollResponse {
        var components = URLComponents(
            url: AppConfig.baseURL.appendingPathComponent("auth/poll"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "loginSessionId", value: loginSessionId)]

        let data = try await perform(URLRequest(url: components.url!))
        return try decode(PollResponse.self, from: data)
    }

    /// Best-effort server-side session revoke. The refresh token goes in the
    /// body because the app has no cookie jar.
    func logout() async {
        guard let refresh = TokenStore.refresh else { return }
        var request = URLRequest(url: AppConfig.baseURL.appendingPathComponent("auth/logout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["refresh": refresh])
        _ = try? await perform(request)
    }

    // MARK: - Authenticated API

    func me() async throws -> AuthUser {
        try await authorized(path: "api/me", method: "GET", body: NoBody?.none)
    }

    /// Catalogue for the region picker. Read-only — listing a region provisions
    /// nothing.
    func regions() async throws -> [Region] {
        let catalog: RegionCatalog = try await authorized(
            path: "api/me/regions", method: "GET", body: NoBody?.none
        )
        return catalog.regions.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Register this device on a region, uploading only the public key.
    /// Idempotent per (user, device, region): calling it again for a region we
    /// already hold returns the same peer rather than allocating a second one.
    func provision(regionCode: String) async throws -> DeviceRegionResponse {
        guard let publicKey = PeerStore.publicKey(for: regionCode) else {
            throw APIError.decoding(KeychainError.dataCorrupted)
        }
        let body = DeviceRegionRequest(
            deviceId: DeviceIdentity.id,
            deviceName: DeviceIdentity.name,
            regionCode: regionCode,
            publicKey: publicKey
        )
        return try await authorized(path: "api/me/devices/regions", method: "POST", body: body)
    }

    func devices() async throws -> [DeviceSummary] {
        let list: DeviceList = try await authorized(
            path: "api/me/devices", method: "GET", body: NoBody?.none
        )
        return list.devices
    }

    /// Revoke this whole device server-side (all its regions at once).
    func revokeDevice(_ deviceId: String) async throws {
        let _: EmptyResponse = try await authorized(
            path: "api/me/devices/\(deviceId)", method: "DELETE", body: NoBody?.none
        )
    }

    /// Issue an authenticated request, refreshing once on a 401 and replaying.
    /// A second 401 after a successful refresh means the session is genuinely
    /// gone (user disabled, session revoked) — surfaced as `.notAuthenticated`
    /// so the UI signs out rather than looping.
    func authorized<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        guard var access = TokenStore.access else { throw APIError.notAuthenticated }

        do {
            let data = try await perform(buildRequest(path: path, method: method, body: body, access: access))
            return try decode(Response.self, from: data)
        } catch let APIError.http(status, _) where status == 401 {
            let session = try await refreshSession()
            access = session.access
            let data = try await perform(buildRequest(path: path, method: method, body: body, access: access))
            return try decode(Response.self, from: data)
        }
    }

    /// Rotate the session. Concurrent callers share one in-flight task; only
    /// the first actually hits the network.
    func refreshSession() async throws -> SessionResponse {
        if let existing = refreshInFlight {
            return try await existing.value
        }

        let task = Task<SessionResponse, Error> { [session] in
            guard let refresh = TokenStore.refresh else { throw APIError.notAuthenticated }

            var request = URLRequest(url: AppConfig.baseURL.appendingPathComponent("auth/refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh": refresh])

            let (data, response) = try await Self.send(request, on: session)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                // 401/403 here means the refresh itself was rejected: the
                // session is unrecoverable, so drop it instead of retrying.
                TokenStore.clear()
                throw APIError.notAuthenticated
            }
            let result: SessionResponse
            do {
                result = try JSONDecoder().decode(SessionResponse.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
            // Persist before returning — the caller is about to use `access`,
            // and the old refresh is already dead server-side.
            try TokenStore.save(result)
            return result
        }

        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }

    // MARK: - Plumbing

    private func buildRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        access: String
    ) -> URLRequest {
        var request = URLRequest(url: AppConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    /// Run a request and map anything non-2xx onto `APIError.http`, pulling the
    /// backend's `{ "error": "..." }` code out of the body when present so the
    /// UI can show a specific message.
    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.send(request, on: session)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, code: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError.http(status: http.statusCode, code: code)
        }
        return data
    }

    private static func send(_ request: URLRequest, on session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // 204 with an empty body is a valid success for the void-returning
        // calls; those decode into `EmptyResponse`.
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

/// Placeholder for endpoints that answer 204 with no body.
struct EmptyResponse: Decodable {}

/// Placeholder for requests that carry no body. Swift needs a concrete
/// `Encodable` to bind the generic against; `Never` does not fit.
struct NoBody: Encodable {}
