import Combine
import Foundation

@MainActor
final class AuthSession: ObservableObject {
    @Published private(set) var user: AuthUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentSessionID: String?

    private let api = FinMateAPIClient()
    private let keychain = KeychainStore()
    private var accessToken: String?
    private var refreshToken: String?

    init() {
        accessToken = try? keychain.read("accessToken")
        refreshToken = try? keychain.read("refreshToken")
        if let savedUser = try? keychain.read("user"),
           let data = savedUser.data(using: .utf8) {
            user = try? JSONDecoder().decode(AuthUser.self, from: data)
        }
    }

    func restore() async {
        guard let refreshToken else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await api.refresh(refreshToken: refreshToken)
            accessToken = response.accessToken
            try keychain.save(response.accessToken, for: "accessToken")
            isAuthenticated = user != nil
        } catch {
            clearSession()
        }
    }

    func login(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let response = try await api.login(email: email, password: password)
        try saveSession(response)
    }

    func register(name: String, email: String, password: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        let response = try await api.register(name: name, email: email, password: password)
        return response.status
    }

    func logout() async {
        if let accessToken {
            try? await api.logout(accessToken: accessToken)
        }
        clearSession()
    }

    func token() -> String? {
        accessToken
    }

    func sessions() async throws -> [RemoteSession] {
        guard let accessToken else { return [] }
        return try await api.listSessions(accessToken: accessToken)
    }

    func revokeSession(_ session: RemoteSession) async throws {
        guard let accessToken, let sessionID = session.sessionId else { return }
        try await api.revokeSession(id: sessionID, accessToken: accessToken)
        if sessionID == currentSessionID { clearSession() }
    }

    private func saveSession(_ response: AuthResponse) throws {
        let userData = try JSONEncoder().encode(response.user)
        guard let userText = String(data: userData, encoding: .utf8) else {
            throw KeychainError.saveFailed
        }
        try keychain.save(response.accessToken, for: "accessToken")
        try keychain.save(response.refreshToken, for: "refreshToken")
        try keychain.save(userText, for: "user")
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        user = response.user
        currentSessionID = response.sessionId
        isAuthenticated = true
    }

    private func clearSession() {
        try? keychain.delete("accessToken")
        try? keychain.delete("refreshToken")
        try? keychain.delete("user")
        accessToken = nil
        refreshToken = nil
        user = nil
        currentSessionID = nil
        isAuthenticated = false
    }
}
