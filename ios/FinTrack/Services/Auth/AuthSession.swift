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

    func checkEmailExists(_ email: String) async throws -> Bool {
        try await api.checkEmailExists(email: email)
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        guard let accessToken else { return }
        try await api.changePassword(oldPassword: oldPassword, newPassword: newPassword, accessToken: accessToken)
    }

    func verifyEmail(token: String) async throws {
        let response = try await api.verifyEmail(token: token)
        try saveSession(response)
    }

    func resendVerification(email: String) async throws {
        try await api.resendVerification(email: email)
    }

    func requestPasswordReset(email: String) async throws {
        try await api.requestPasswordReset(email: email)
    }

    func resetPassword(token: String, newPassword: String) async throws {
        try await api.resetPassword(token: token, newPassword: newPassword)
        clearSession()
    }

    func uploadAvatar(dataURI: String) async throws {
        guard let accessToken, let user else { return }
        let response = try await api.uploadAvatar(dataURI: dataURI, accessToken: accessToken)
        self.user = AuthUser(id: user.id, name: user.name, email: user.email, avatar: response.avatar)
        try saveUser(self.user)
    }

    func setMonthlyEmailPreference(optIn: Bool) async throws {
        guard let accessToken else { return }
        try await api.setMonthlyEmailPreference(optIn: optIn, accessToken: accessToken)
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
        try keychain.save(response.accessToken, for: "accessToken")
        try keychain.save(response.refreshToken, for: "refreshToken")
        try saveUser(response.user)
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        user = response.user
        currentSessionID = response.sessionId
        isAuthenticated = true
    }

    private func saveUser(_ user: AuthUser?) throws {
        guard let user,
              let userData = try? JSONEncoder().encode(user),
              let userText = String(data: userData, encoding: .utf8) else {
            throw KeychainError.saveFailed
        }
        try keychain.save(userText, for: "user")
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
