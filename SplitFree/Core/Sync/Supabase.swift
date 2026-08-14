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
        if !raw.lowercased().hasPrefix("http") {
            // Loopback means a stack running on this machine, which serves plain
            // HTTP. Inferring it is what lets the scheme stay out of the config
            // file entirely, which is the point: `//` starts a comment there.
            let isLoopback = raw.hasPrefix("127.0.0.1")
                || raw.hasPrefix("localhost")
                || raw.hasPrefix("[::1]")
            raw = (isLoopback ? "http://" : "https://") + raw
        }
        return URL(string: raw)
    }()

    static let anonKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String
        else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }()

    static var isConfigured: Bool { url != nil && anonKey != nil }

}

// MARK: - Session

struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String

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

    func restoreSession() -> SupabaseSession? {
        current = SessionStore.load()
        return current
    }

    // MARK: Identity

    /// Gets an identity without asking anybody for anything.
    ///
    /// Sharing needs row level security to have something to key on, and that
    /// is all it needs. There is no email, no password and no screen: the first
    /// time somebody shares or joins, the device quietly becomes a user.
    ///
    /// The trade is recovery. Lose the device and the session goes with it, and
    /// a friend has to send a fresh code. On iPhone the Keychain usually
    /// survives a restore, so in practice this bites rarely.
    @discardableResult
    func signInAnonymously() async throws -> SupabaseSession {
        if let current, !current.isExpired { return current }
        let data = try await request(path: "/auth/v1/signup", method: "POST", body: [:], authorized: false)
        return try store(tokenResponse: data)
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
            struct User: Decodable { let id: String }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw SupabaseError.decoding("token")
        }
        let session = SupabaseSession(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date().addingTimeInterval(payload.expires_in ?? 3600),
            userID: payload.user?.id ?? ""
        )
        current = session
        SessionStore.save(session)
        return session
    }

    private func validSession() async throws -> SupabaseSession {
        guard let existing = current else { return try await signInAnonymously() }
        guard existing.isExpired else { return existing }

        if let refreshTask { return try await refreshTask.value }
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
            // A dead refresh token is not worth surfacing when the identity is
            // disposable. Take a fresh one.
            signOut()
            return try await signInAnonymously()
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

        // Authorization carries a user's session and nothing else. The older
        // anon key was a JWT and could stand in for one, which is why so much
        // sample code sends it here; the newer publishable keys are not JWTs, and
        // a server asked to parse one as a token rejects the request. The apikey
        // header is what identifies the project, and it is set above either way.
        if authorized {
            let session = try await validSession()
            urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
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
