#if DEBUG
import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

/// Development-only account, consent and explicitly enabled shopping sync transport.
/// See docs/requirements.md: shopping / ChatGPT integration.
@MainActor
final class ShoppingConnectionService: ObservableObject {
    static let shared = ShoppingConnectionService()
    static let pluginURL = URL(string: "https://chatgpt.com/plugins/plugin_asdk_app_6aca4c016e688191ae17c3440cb97dc1")!
    private static let apiOrigin = "https://lifelify-api-dev.inazumimakoto.workers.dev"

    struct Challenge: Decodable {
        let id: String
        let nonce: String
        let expires_at: TimeInterval
        var isUsable: Bool { expires_at > Date().timeIntervalSince1970 + 5 }
    }

    struct ApprovalRequest: Decodable {
        let id: String
        let client_name: String
        let client_domain: String
        let callback_host: String
        let scopes: [String]
        let expires_at: TimeInterval
        var isExpired: Bool { expires_at <= Date().timeIntervalSince1970 }
    }

    enum Decision: String, Encodable {
        case approve, deny
    }

    enum ConnectionError: LocalizedError {
        case unavailable, invalidResponse, signInRequired, expired, keychain, locked, unsupportedScope, rateLimited

        var errorDescription: String? {
            switch self {
            case .unavailable: return String(localized: "shopping.connection.error.unavailable")
            case .invalidResponse: return String(localized: "shopping.connection.error.invalid")
            case .signInRequired: return String(localized: "shopping.connection.error.signin")
            case .expired: return String(localized: "shopping.connection.error.expired")
            case .keychain: return String(localized: "shopping.connection.error.keychain")
            case .locked: return String(localized: "shopping.connection.error.locked")
            case .unsupportedScope: return String(localized: "shopping.connection.error.scope")
            case .rateLimited: return String(localized: "shopping.connection.error.rate")
            }
        }
    }

    @Published private(set) var accountID: String?
    @Published private(set) var challenge: Challenge?
    @Published private(set) var isBusy = false
    @Published private(set) var approvalRequestID: String?
    @Published private(set) var presentationRequested = false
    @Published var errorMessage: String?

    private struct User: Codable { let id: String }
    private struct SessionResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: TimeInterval
        let refresh_expires_in: TimeInterval
        let user: User
    }
    private struct Credentials: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let refreshExpiresAt: Date
        let userID: String
    }
    private struct SessionStatus: Decodable { let user: User }
    private struct DecisionResponse: Decodable { let status: String }
    private struct HTTPFailure: Error { let status: Int; let body: Data }

    private var credentials: Credentials?
    private var pendingKeychainCredentials: Credentials?
    private var activeAppleChallenge: Challenge?
    private var refreshTask: _Concurrency.Task<Credentials, Error>?
    private var sessionGeneration = 0
    private var didRestore = false
    private var queuedApprovalIDs: [String] = []
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    // URLSession invalidation is thread-safe and does not read UI state. Explicitly avoid
    // an isolated deinit: Swift 6.2's MainActor back-deployment helper can crash when a
    // synchronous caller releases the service without a Swift concurrency task.
    nonisolated deinit {
        session.invalidateAndCancel()
    }

    func showConnection() {
        presentationRequested = true
    }

    /// URL data identifies a pending request, never an account or an authorization decision.
    @discardableResult
    func handleApprovalURL(_ url: URL) -> Bool {
        guard let id = Self.approvalID(from: url) else { return false }
        if id != approvalRequestID && !queuedApprovalIDs.contains(id) {
            if approvalRequestID == nil { approvalRequestID = id }
            else { queuedApprovalIDs.append(id) }
        }
        presentationRequested = true
        return true
    }

    static func approvalID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "lifelify-connect-dev.inazumimakoto.workers.dev",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let path = components.percentEncodedPath
        guard path.hasPrefix("/connect/") else { return nil }
        let id = String(path.dropFirst("/connect/".count))
        guard id.count == 43, id.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        return id
    }

    func dismissConnection() {
        approvalRequestID = queuedApprovalIDs.isEmpty ? nil : queuedApprovalIDs.removeFirst()
        presentationRequested = approvalRequestID != nil
    }

    func restoreSession() async {
        guard (!didRestore || errorMessage != nil), !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            // Preserve a rotated token in memory if a previous secure-storage write was interrupted.
            if let pendingKeychainCredentials {
                try SessionKeychain.save(pendingKeychainCredentials)
                self.pendingKeychainCredentials = nil
            }
            let saved = try SessionKeychain.read()
            credentials = saved
            accountID = saved?.userID
            // A locked Keychain must remain retryable, not be interpreted as a missing account.
            didRestore = true
            guard saved != nil else { return }
            let status: SessionStatus = try await authorizedRequest(path: "/auth/native/session")
            guard status.user.id == saved?.userID else {
                try clearSession()
                throw ConnectionError.invalidResponse
            }
        } catch {
            report(error)
        }
    }

    func prepareAppleChallenge() async {
        guard !isBusy, accountID == nil else { return }
        challenge = nil
        activeAppleChallenge = nil
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            // Check secure storage before allowing a new account to replace an unreadable session.
            if !didRestore {
                let saved = try SessionKeychain.read()
                credentials = saved
                accountID = saved?.userID
                didRestore = true
                if saved != nil { return }
            }
            let result: Challenge = try await request(path: "/auth/native/apple/challenge", method: "POST", body: Data("{}".utf8))
            guard !result.id.isEmpty, !result.nonce.isEmpty, result.isUsable else { throw ConnectionError.invalidResponse }
            challenge = result
        } catch {
            report(error)
        }
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard let prepared = challenge, prepared.isUsable else {
            activeAppleChallenge = nil
            errorMessage = ConnectionError.expired.localizedDescription
            return
        }
        activeAppleChallenge = prepared
        isBusy = true
        request.requestedScopes = []
        request.nonce = SHA256.hash(data: Data(prepared.nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func finishAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        let prepared = activeAppleChallenge
        activeAppleChallenge = nil
        challenge = nil
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let authorization = try result.get()
            guard let prepared, prepared.isUsable,
                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { throw ConnectionError.expired }
            let body = try JSONEncoder().encode(["challenge_id": prepared.id, "id_token": token])
            let result: SessionResponse = try await request(path: "/auth/native/apple/session", method: "POST", body: body)
            let stored = try makeCredentials(result)
            try SessionKeychain.save(stored)
            sessionGeneration += 1
            refreshTask?.cancel()
            refreshTask = nil
            credentials = stored
            pendingKeychainCredentials = nil
            accountID = stored.userID
            didRestore = true
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // Cancellation leaves the existing account untouched; the user can prepare a new challenge.
        } catch {
            report(error)
        }
    }

    func logout() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let current = try await validCredentials()
            try requireUnlocked()
            _ = try await data(path: "/auth/native/logout", method: "POST", token: current.accessToken, body: Data("{}".utf8))
            try clearSession()
        } catch {
            report(error)
        }
    }

    func loadApproval(id: String) async throws -> ApprovalRequest {
        try requireUnlocked()
        let result: ApprovalRequest = try await authorizedRequest(path: "/auth/app/requests/\(id)")
        guard result.id == id, !result.isExpired,
              !result.client_name.isEmpty else { throw ConnectionError.expired }
        guard result.callback_host == "chatgpt.com" else { throw ConnectionError.invalidResponse }
        let supported: Set<String> = ["shopping:read", "shopping:write", "offline_access"]
        guard !result.scopes.isEmpty, result.scopes.allSatisfy(supported.contains) else { throw ConnectionError.unsupportedScope }
        return result
    }

    func decide(_ decision: Decision, request: ApprovalRequest, accountID expectedAccountID: String) async throws {
        guard !request.isExpired, approvalRequestID == request.id else { throw ConnectionError.expired }
        let current = try await validCredentials()
        guard current.userID == expectedAccountID else { throw ConnectionError.signInRequired }
        try requireUnlocked()
        let body = try JSONEncoder().encode(["decision": decision.rawValue])
        // Do not retry a mutation after an uncertain response. The original browser can confirm its outcome.
        let response: DecisionResponse = try await self.request(path: "/auth/app/requests/\(request.id)", method: "POST", token: current.accessToken, body: body)
        guard response.status == (decision == .approve ? "approved" : "denied") else { throw ConnectionError.invalidResponse }
    }

    static func resumeURL(for requestID: String) -> URL? {
        guard requestID.count == 43,
              requestID.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        var components = URLComponents(string: apiOrigin + "/auth/app/resume")!
        components.queryItems = [URLQueryItem(name: "id", value: requestID)]
        return components.url
    }

    func shoppingChanges(after cursor: Int64, ownerID: UUID) async throws -> ShoppingSyncPage {
        guard cursor >= 0 else { throw ConnectionError.invalidResponse }
        return try await shoppingRequest(path: "/auth/native/shopping/changes?after=\(cursor)&limit=100", ownerID: ownerID)
    }

    func sendShoppingMutation(_ mutation: ShoppingSyncMutation, ownerID: UUID) async throws -> ShoppingSyncMutationResponse {
        let body = try JSONEncoder().encode(mutation)
        return try await shoppingRequest(path: "/auth/native/shopping/mutations", method: "POST", body: body, ownerID: ownerID)
    }

    private func shoppingRequest<Response: Decodable>(path: String, method: String = "GET", body: Data? = nil,
                                                       ownerID: UUID) async throws -> Response {
        let current = try await validCredentials()
        try requireUnlocked()
        guard UUID(uuidString: current.userID) == ownerID else { throw ShoppingSyncError.accountMismatch }
        do {
            return try await request(path: path, method: method, token: current.accessToken, body: body)
        } catch let failure as HTTPFailure where failure.status == 401 {
            let refreshed = try await validCredentials(forceRefresh: credentials?.accessToken == current.accessToken)
            try requireUnlocked()
            guard UUID(uuidString: refreshed.userID) == ownerID else { throw ShoppingSyncError.accountMismatch }
            // The same operation ID/body makes a refresh retry safe even if the first write was accepted.
            return try await shoppingResponse(path: path, method: method, body: body, token: refreshed.accessToken)
        } catch let failure as HTTPFailure where failure.status == 409 {
            throw try syncConflict(failure)
        }
    }

    private func shoppingResponse<Response: Decodable>(path: String, method: String, body: Data?, token: String) async throws -> Response {
        do { return try await request(path: path, method: method, token: token, body: body) }
        catch let failure as HTTPFailure where failure.status == 409 { throw try syncConflict(failure) }
    }

    private func syncConflict(_ failure: HTTPFailure) throws -> ShoppingSyncConflictFailure {
        let response = try JSONDecoder().decode(ShoppingSyncConflictResponse.self, from: failure.body)
        guard ["version_conflict", "place_unavailable"].contains(response.error) else { throw ConnectionError.invalidResponse }
        return ShoppingSyncConflictFailure(response: response)
    }

    func localizedMessage(for error: Error) -> String {
        if let error = error as? ConnectionError { return error.localizedDescription }
        if let failure = error as? HTTPFailure {
            switch failure.status {
            case 401: return ConnectionError.signInRequired.localizedDescription
            case 404, 409, 410: return ConnectionError.expired.localizedDescription
            case 429: return ConnectionError.rateLimited.localizedDescription
            default: return ConnectionError.unavailable.localizedDescription
            }
        }
        return ConnectionError.unavailable.localizedDescription
    }

    private func report(_ error: Error) {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        errorMessage = localizedMessage(for: error)
    }

    private func requireUnlocked() throws {
        let lock = AppLockService.shared
        guard !lock.isAppLockEnabled || lock.isUnlocked else { throw ConnectionError.locked }
    }

    private func authorizedRequest<Response: Decodable>(path: String) async throws -> Response {
        let current = try await validCredentials()
        do {
            return try await request(path: path, token: current.accessToken)
        } catch let failure as HTTPFailure where failure.status == 401 {
            let refreshed = try await validCredentials(forceRefresh: credentials?.accessToken == current.accessToken)
            return try await request(path: path, token: refreshed.accessToken)
        }
    }

    private func validCredentials(forceRefresh: Bool = false) async throws -> Credentials {
        if let pendingKeychainCredentials {
            try SessionKeychain.save(pendingKeychainCredentials)
            self.pendingKeychainCredentials = nil
        }
        guard let current = credentials else { throw ConnectionError.signInRequired }
        if let refreshTask { return try await refreshTask.value }
        if !forceRefresh && current.expiresAt.timeIntervalSinceNow > 30 { return current }
        guard current.refreshExpiresAt > Date() else {
            try clearSession()
            throw ConnectionError.signInRequired
        }
        let generation = sessionGeneration
        let task = _Concurrency.Task { @MainActor [self] in
            do {
                let body = try JSONEncoder().encode(["refresh_token": current.refreshToken])
                let response: SessionResponse = try await request(path: "/auth/native/refresh", method: "POST", body: body)
                let updated = try makeCredentials(response)
                guard generation == sessionGeneration, updated.userID == current.userID else { throw ConnectionError.signInRequired }
                credentials = updated
                accountID = updated.userID
                pendingKeychainCredentials = updated
                try SessionKeychain.save(updated)
                pendingKeychainCredentials = nil
                return updated
            } catch let failure as HTTPFailure where [400, 401, 403].contains(failure.status) {
                if generation == sessionGeneration { try clearSession() }
                throw ConnectionError.signInRequired
            }
        }
        refreshTask = task
        defer { if generation == sessionGeneration { refreshTask = nil } }
        return try await task.value
    }

    private func makeCredentials(_ response: SessionResponse) throws -> Credentials {
        guard UUID(uuidString: response.user.id) != nil,
              !response.access_token.isEmpty, !response.refresh_token.isEmpty,
              response.expires_in > 0, response.refresh_expires_in > 0 else { throw ConnectionError.invalidResponse }
        return Credentials(accessToken: response.access_token, refreshToken: response.refresh_token,
                           expiresAt: Date().addingTimeInterval(response.expires_in),
                           refreshExpiresAt: Date().addingTimeInterval(response.refresh_expires_in), userID: response.user.id)
    }

    private func clearSession() throws {
        try SessionKeychain.delete()
        sessionGeneration += 1
        refreshTask = nil
        credentials = nil
        pendingKeychainCredentials = nil
        accountID = nil
        challenge = nil
        activeAppleChallenge = nil
    }

    private func request<Response: Decodable>(path: String, method: String = "GET", token: String? = nil, body: Data? = nil) async throws -> Response {
        let response = try await data(path: path, method: method, token: token, body: body)
        do { return try JSONDecoder().decode(Response.self, from: response) }
        catch { throw ConnectionError.invalidResponse }
    }

    private func data(path: String, method: String, token: String?, body: Data?) async throws -> Data {
        guard path.hasPrefix("/auth/"), let url = URL(string: Self.apiOrigin + path) else { throw ConnectionError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == url.host else { throw ConnectionError.invalidResponse }
        let maximum = path.hasPrefix("/auth/native/shopping/") ? 4_194_304 : 65_536
        guard data.count <= maximum else { throw ConnectionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw HTTPFailure(status: http.statusCode, body: data) }
        return data
    }

    private enum SessionKeychain {
        private static var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: "com.inazumimakoto.lifelog.shopping.connection.dev",
             kSecAttrAccount as String: "native-session",
             kSecAttrSynchronizable as String: false]
        }

        static func read() throws -> Credentials? {
            var query = query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw ConnectionError.keychain }
            do { return try JSONDecoder().decode(Credentials.self, from: data) }
            catch { throw ConnectionError.keychain }
        }

        static func save(_ credentials: Credentials) throws {
            let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credentials),
                                           kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
                guard added == errSecSuccess else { throw ConnectionError.keychain }
            } else if status != errSecSuccess { throw ConnectionError.keychain }
        }

        static func delete() throws {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ConnectionError.keychain }
        }
    }
}

nonisolated private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
