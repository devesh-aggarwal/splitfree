import Foundation
import Security

/// Where the backend lives, and whether there is one at all.
///
/// Both values come from the app's Info.plist so the open-source repo doesn't
/// carry anyone's project keys. When they're absent, `isConfigured` is false and
/// the whole sync feature stays switched off: the app is exactly the local-only
/// app it was before, which is the point of making accounts optional.
enum SupabaseConfig {
    /// The project's base URL.
    ///
    /// The scheme is optional in the config file and added here when missing.
    /// That is not politeness: `//` starts a comment in an xcconfig, so a pasted
    /// `https://…` is silently truncated to `https:` and every request fails
    /// with nothing on screen to explain it. Accepting a bare host removes the
    /// trap rather than documenting it.
    static let url: URL? = {
        guard var raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String else {
            return nil
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard !raw.isEmpty, raw != "https:", raw != "http:" else { return nil }
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        return URL(string: raw)
    }()

    static let anonKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String
        else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }()

    static var isConfigured: Bool { url != nil && anonKey != nil }

    /// Where an OAuth provider sends the browser back to. Must match the URL
    /// scheme in Info.plist and the redirect list in the Supabase dashboard.
    static let redirectURI = "splitfree://auth-callback"
}

// MARK: - Session

struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?

    /// Treated as expired a minute early, so a request never leaves with a token
    /// that dies in flight.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

/// Session storage. The Keychain rather than UserDefaults, because a refresh
/// token is a long-lived credential.
enum SessionStore {
    private static let service = "com.splitfree.session"
    private static let account = "supabase"

    static func save(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> SupabaseSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case notSignedIn
    case http(status: Int, message: String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "This build isn't set up for syncing.")
        case .notSignedIn:
            String(localized: "Sign in to sync.")
        case .http(let status, let message):
            message.isEmpty
                ? String(format: String(localized: "The server returned an error (%lld).", comment: "HTTP status"), status)
                : message
        case .decoding:
            String(localized: "The server sent something SplitFree didn't understand.")
        case .network(let message):
            message
        }
    }
}

// MARK: - Client

/// A small, dependency-free Supabase client: GoTrue for auth, PostgREST for
/// data, and RPC for the sync and invite functions.
///
/// Only the handful of endpoints this app actually uses are implemented. That's
/// a few hundred lines against pulling in an SDK, and it keeps the promise in
/// the README that the app has no third-party dependencies.
actor SupabaseClient {
    static let shared = SupabaseClient()

    private let session: URLSession
    private var current: SupabaseSession?
    /// Serialises refreshes so ten parallel requests don't each spend the
    /// refresh token, which would invalidate the other nine.
    private var refreshTask: Task<SupabaseSession, Error>?

    init(session: URLSession = .shared) {
        self.session = session
        self.current = SessionStore.load()
    }

    var isSignedIn: Bool { current != nil }
    var userID: String? { current?.userID }
    var email: String? { current?.email }

    func restoreSession() -> SupabaseSession? {
        current = SessionStore.load()
        return current
    }

    // MARK: Auth

    /// Sends a six-digit code to an email address. No password to forget, and no
    /// third-party SDK.
    func sendEmailCode(to email: String) async throws {
        _ = try await request(
            path: "/auth/v1/otp",
            method: "POST",
            body: ["email": email, "create_user": true],
            authorized: false
        )
    }

    func verifyEmailCode(email: String, code: String) async throws -> SupabaseSession {
        let data = try await request(
            path: "/auth/v1/verify",
            method: "POST",
            body: ["email": email, "token": code, "type": "email"],
            authorized: false
        )
        return try store(tokenResponse: data)
    }

    /// Exchanges an Apple identity token for a Supabase session. The token comes
    /// from `ASAuthorizationAppleIDProvider`, so the user never leaves the app.
    func signInWithApple(idToken: String, nonce: String?) async throws -> SupabaseSession {
        var body: [String: Any] = ["provider": "apple", "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        let data = try await request(
            path: "/auth/v1/token?grant_type=id_token",
            method: "POST",
            body: body,
            authorized: false
        )
        return try store(tokenResponse: data)
    }

    /// The URL to open in a browser for a provider that has no native flow.
    nonisolated func oauthURL(provider: String) -> URL? {
        guard let base = SupabaseConfig.url else { return nil }
        var components = URLComponents(
            url: base.appendingPathComponent("/auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.redirectURI),
        ]
        return components?.url
    }

    /// Completes a browser OAuth round trip. Supabase returns the tokens in the
    /// URL fragment.
    func completeOAuth(callback: URL) throws -> SupabaseSession {
        guard let fragment = callback.fragment else {
            throw SupabaseError.network(String(localized: "Sign-in was cancelled."))
        }
        var values: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1]).removingPercentEncoding
        }
        guard let accessToken = values["access_token"],
              let refreshToken = values["refresh_token"]
        else {
            throw SupabaseError.network(values["error_description"] ?? String(localized: "Sign-in failed."))
        }
        let expiresIn = Double(values["expires_in"] ?? "3600") ?? 3600
        let session = SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userID: Self.userID(fromJWT: accessToken) ?? "",
            email: nil
        )
        current = session
        SessionStore.save(session)
        return session
    }

    func signOut() {
        current = nil
        refreshTask = nil
        SessionStore.clear()
    }

    private func store(tokenResponse data: Data) throws -> SupabaseSession {
        struct Payload: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double?
            let user: User?
            struct User: Decodable {
                let id: String
                let email: String?
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw SupabaseError.decoding("token")
        }
        let session = SupabaseSession(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date().addingTimeInterval(payload.expires_in ?? 3600),
            userID: payload.user?.id ?? Self.userID(fromJWT: payload.access_token) ?? "",
            email: payload.user?.email
        )
        current = session
        SessionStore.save(session)
        return session
    }

    /// Reads `sub` out of the JWT payload. Only used when the token endpoint
    /// doesn't echo the user back; the value is not trusted for anything
    /// security-sensitive, which the server decides for itself.
    private nonisolated static func userID(fromJWT token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["sub"] as? String
    }

    private func validSession() async throws -> SupabaseSession {
        guard let existing = current else { throw SupabaseError.notSignedIn }
        guard existing.isExpired else { return existing }

        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task<SupabaseSession, Error> {
            let data = try await request(
                path: "/auth/v1/token?grant_type=refresh_token",
                method: "POST",
                body: ["refresh_token": existing.refreshToken],
                authorized: false
            )
            return try store(tokenResponse: data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch {
            // A refresh token that no longer works means the session is over.
            signOut()
            throw SupabaseError.notSignedIn
        }
    }

    // MARK: Data

    /// Calls a Postgres function. Everything the sync engine does goes through
    /// one of these.
    func rpc(_ name: String, arguments: [String: Any] = [:]) async throws -> Data {
        try await request(path: "/rest/v1/rpc/\(name)", method: "POST", body: arguments, authorized: true)
    }

    /// Inserts or updates rows, keyed by primary key.
    func upsert(table: String, rows: [[String: Any]], onConflict: String? = nil) async throws {
        guard !rows.isEmpty else { return }
        var path = "/rest/v1/\(table)"
        if let onConflict { path += "?on_conflict=\(onConflict)" }
        _ = try await request(
            path: path,
            method: "POST",
            bodyArray: rows,
            authorized: true,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    // MARK: Transport

    private func request(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        bodyArray: [[String: Any]]? = nil,
        authorized: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let base = SupabaseConfig.url, let anonKey = SupabaseConfig.anonKey else {
            throw SupabaseError.notConfigured
        }

        var urlRequest = URLRequest(url: base.appendingPathComponent(path))
        // `appendingPathComponent` escapes the query string, so rebuild when one
        // is present.
        if path.contains("?"), let direct = URL(string: base.absoluteString + path) {
            urlRequest = URLRequest(url: direct)
        }
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 30
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if authorized {
            let session = try await validSession()
            urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            urlRequest.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else if let bodyArray {
            urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: bodyArray)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw SupabaseError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.network(String(localized: "No response from the server."))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    /// Supabase reports failures in a few different shapes depending on which
    /// component answered.
    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        for key in ["msg", "message", "error_description", "error", "hint", "details"] {
            if let value = json[key] as? String, !value.isEmpty { return value }
        }
        return ""
    }
}
