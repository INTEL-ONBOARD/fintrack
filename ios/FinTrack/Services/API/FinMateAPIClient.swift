import Foundation

enum FinMateAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The FinMate API address is invalid."
        case .invalidResponse:
            return "FinMate returned an invalid response."
        case let .server(_, message):
            return message
        case .emptyResponse:
            return "FinMate returned an empty response."
        }
    }
}

struct FinMateAPIClient {
    static let baseURL = URL(string: "https://finmate.com.lk/finwise")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(LoginRequest(email: email, password: password))
        return try await send(path: "/api/auth/login", method: "POST", body: body)
    }

    func register(name: String, email: String, password: String) async throws -> VerificationResponse {
        let body = try JSONEncoder().encode(
            RegisterRequest(name: name, email: email, password: password)
        )
        return try await send(path: "/api/auth/register", method: "POST", body: body)
    }

    func checkEmailExists(email: String) async throws -> Bool {
        let response: EmailExistsResponse = try await send(
            path: "/api/auth/exists", method: "GET",
            queryItems: [URLQueryItem(name: "email", value: email)]
        )
        return response.exists
    }

    func changePassword(oldPassword: String, newPassword: String, accessToken: String) async throws {
        let body = try JSONEncoder().encode(ChangePasswordRequest(oldPassword: oldPassword, newPassword: newPassword))
        let _: APIStatusResponse = try await send(path: "/api/auth/change-password", method: "POST", body: body, accessToken: accessToken)
    }

    func verifyEmail(token: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(TokenRequest(token: token))
        return try await send(path: "/api/auth/verify", method: "POST", body: body)
    }

    func resendVerification(email: String) async throws {
        let body = try JSONEncoder().encode(EmailRequest(email: email))
        let _: APIStatusResponse = try await send(path: "/api/auth/resend-verification", method: "POST", body: body)
    }

    func requestPasswordReset(email: String) async throws {
        let body = try JSONEncoder().encode(EmailRequest(email: email))
        let _: APIStatusResponse = try await send(path: "/api/auth/forgot-password", method: "POST", body: body)
    }

    func resetPassword(token: String, newPassword: String) async throws {
        let body = try JSONEncoder().encode(ResetPasswordRequest(token: token, newPassword: newPassword))
        let _: APIStatusResponse = try await send(path: "/api/auth/reset-password", method: "POST", body: body)
    }

    func uploadAvatar(dataURI: String, accessToken: String) async throws -> AvatarResponse {
        let body = try JSONEncoder().encode(AvatarRequest(avatar: dataURI))
        return try await send(path: "/api/user/avatar", method: "POST", body: body, accessToken: accessToken)
    }

    func setMonthlyEmailPreference(optIn: Bool, accessToken: String) async throws {
        let body = try JSONEncoder().encode(MonthlyEmailRequest(optIn: optIn))
        let _: APIStatusResponse = try await send(path: "/api/email/monthly-opt-in", method: "POST", body: body, accessToken: accessToken)
    }

    func unsubscribeEmail(token: String?) async throws {
        let queryItems = token.map { [URLQueryItem(name: "token", value: $0)] } ?? []
        let _: APIStatusResponse = try await send(path: "/api/email/unsubscribe", method: "GET", queryItems: queryItems)
    }

    func deleteUserData(accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/user/data", method: "DELETE", accessToken: accessToken)
    }

    func listChatUsers(accessToken: String) async throws -> [RemoteChatUser] {
        try await send(path: "/api/chat/users", method: "GET", accessToken: accessToken)
    }

    func listConversations(accessToken: String) async throws -> [RemoteConversation] {
        try await send(path: "/api/chat/conversations", method: "GET", accessToken: accessToken)
    }

    func listMessages(conversationID: String, limit: Int = 40, before: String? = nil, accessToken: String) async throws -> [RemoteMessage] {
        var queryItems = [
            URLQueryItem(name: "conversationId", value: conversationID),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let before { queryItems.append(URLQueryItem(name: "before", value: before)) }
        return try await send(path: "/api/chat/messages", method: "GET", queryItems: queryItems, accessToken: accessToken)
    }

    func sendMessage(conversationID: String, body: String, accessToken: String) async throws -> SendMessageResponse {
        let requestBody = try JSONEncoder().encode(SendMessageRequest(conversationId: conversationID, body: body))
        return try await send(path: "/api/chat/messages", method: "POST", body: requestBody, accessToken: accessToken)
    }

    func refresh(refreshToken: String) async throws -> RefreshResponse {
        let body = try JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))
        return try await send(path: "/api/auth/refresh", method: "POST", body: body)
    }

    func logout(accessToken: String) async throws {
        let _: LogoutResponse = try await send(
            path: "/api/auth/logout", method: "POST", accessToken: accessToken
        )
    }

    func listTransactions(accessToken: String, limit: Int = 500, skip: Int = 0) async throws -> [RemoteTransaction] {
        try await send(
            path: "/api/transactions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "skip", value: String(skip))
            ],
            accessToken: accessToken
        )
    }

    func createTransaction(
        _ transaction: FinanceTransaction,
        categoryName: String?,
        accessToken: String
    ) async throws -> RemoteTransaction {
        let body = try JSONEncoder().encode(
            RemoteTransactionRequest(transaction: transaction, categoryName: categoryName)
        )
        return try await send(
            path: "/api/transactions",
            method: "POST",
            body: body,
            accessToken: accessToken
        )
    }

    func updateTransaction(
        id: String,
        _ transaction: FinanceTransaction,
        categoryName: String?,
        accessToken: String
    ) async throws {
        let body = try JSONEncoder().encode(
            RemoteTransactionRequest(transaction: transaction, categoryName: categoryName)
        )
        let _: APIStatusResponse = try await send(
            path: "/api/transactions/\(id)",
            method: "PATCH",
            body: body,
            accessToken: accessToken
        )
    }

    func deleteTransaction(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(
            path: "/api/transactions/\(id)",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func listAccounts(accessToken: String, limit: Int = 100, skip: Int = 0) async throws -> [RemoteAccount] {
        try await send(path: "/api/accounts", method: "GET", queryItems: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "skip", value: String(skip))
        ], accessToken: accessToken)
    }

    func createAccount(_ account: FinanceAccount, accessToken: String) async throws -> RemoteAccount {
        let body = try JSONEncoder().encode(RemoteAccountRequest(account: account))
        return try await send(path: "/api/accounts", method: "POST", body: body, accessToken: accessToken)
    }

    func updateAccount(id: String, _ account: FinanceAccount, accessToken: String) async throws {
        let body = try JSONEncoder().encode(RemoteAccountRequest(account: account))
        let _: APIStatusResponse = try await send(path: "/api/accounts/\(id)", method: "PATCH", body: body, accessToken: accessToken)
    }

    func deleteAccount(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/accounts/\(id)", method: "DELETE", accessToken: accessToken)
    }

    func listGoals(accessToken: String, limit: Int = 100, skip: Int = 0) async throws -> [RemoteGoal] {
        try await send(path: "/api/goals", method: "GET", queryItems: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "skip", value: String(skip))
        ], accessToken: accessToken)
    }

    func createGoal(_ goal: FinanceGoal, accessToken: String) async throws -> RemoteGoal {
        let body = try JSONEncoder().encode(RemoteGoalRequest(goal: goal))
        return try await send(path: "/api/goals", method: "POST", body: body, accessToken: accessToken)
    }

    func updateGoal(id: String, _ goal: FinanceGoal, accessToken: String) async throws {
        let body = try JSONEncoder().encode(RemoteGoalRequest(goal: goal))
        let _: APIStatusResponse = try await send(path: "/api/goals/\(id)", method: "PATCH", body: body, accessToken: accessToken)
    }

    func deleteGoal(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/goals/\(id)", method: "DELETE", accessToken: accessToken)
    }

    func listBills(accessToken: String, limit: Int = 100, skip: Int = 0) async throws -> [RemoteBill] {
        try await send(path: "/api/bills", method: "GET", queryItems: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "skip", value: String(skip))
        ], accessToken: accessToken)
    }

    func createBill(_ bill: FinanceBill, accessToken: String) async throws -> RemoteBill {
        let body = try JSONEncoder().encode(RemoteBillRequest(bill: bill))
        return try await send(path: "/api/bills", method: "POST", body: body, accessToken: accessToken)
    }

    func updateBill(id: String, _ bill: FinanceBill, accessToken: String) async throws {
        let body = try JSONEncoder().encode(RemoteBillRequest(bill: bill))
        let _: APIStatusResponse = try await send(path: "/api/bills/\(id)", method: "PATCH", body: body, accessToken: accessToken)
    }

    func deleteBill(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/bills/\(id)", method: "DELETE", accessToken: accessToken)
    }

    func toggleBillPaid(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/bills/\(id)/toggle-paid", method: "POST", accessToken: accessToken)
    }

    func listNotifications(accessToken: String, limit: Int = 100, skip: Int = 0) async throws -> [RemoteNotification] {
        try await send(path: "/api/notifications", method: "GET", queryItems: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "skip", value: String(skip))
        ], accessToken: accessToken)
    }

    func createNotification(_ notification: FinanceNotification, accessToken: String) async throws -> RemoteNotification {
        let body = try JSONEncoder().encode(RemoteNotificationRequest(notification: notification))
        return try await send(path: "/api/notifications", method: "POST", body: body, accessToken: accessToken)
    }

    func updateNotification(id: String, _ notification: FinanceNotification, accessToken: String) async throws {
        let body = try JSONEncoder().encode(RemoteNotificationRequest(notification: notification))
        let _: APIStatusResponse = try await send(path: "/api/notifications/\(id)", method: "PATCH", body: body, accessToken: accessToken)
    }

    func deleteNotification(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/notifications/\(id)", method: "DELETE", accessToken: accessToken)
    }

    func markNotificationRead(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/notifications/\(id)/read", method: "POST", accessToken: accessToken)
    }

    func markAllNotificationsRead(accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/notifications/read-all", method: "POST", accessToken: accessToken)
    }

    func getSettings(accessToken: String) async throws -> RemoteSettings? {
        try await send(path: "/api/settings", method: "GET", accessToken: accessToken)
    }

    func saveSettings(_ settings: FinanceUserSettings, accessToken: String) async throws {
        let body = try JSONEncoder().encode(RemoteSettingsRequest(settings: settings))
        let _: APIStatusResponse = try await send(path: "/api/settings", method: "PUT", body: body, accessToken: accessToken)
    }

    func listSessions(accessToken: String) async throws -> [RemoteSession] {
        try await send(path: "/api/sessions", method: "GET", accessToken: accessToken)
    }

    func revokeSession(id: String, accessToken: String) async throws {
        let _: APIStatusResponse = try await send(path: "/api/sessions/\(id)", method: "DELETE", accessToken: accessToken)
    }

    func analyzeStatement(fileData: Data, fileName: String, accessToken: String) async throws -> StatementAnalysis {
        try await sendMultipart(
            path: "/api/import/analyze", fileData: fileData, fileName: fileName,
            fields: [:], accessToken: accessToken
        )
    }

    func commitStatement(
        fileData: Data, fileName: String, accountName: String,
        mapping: StatementMapping, categoryOverrides: [Int: String] = [:],
        fingerprint: String?, bankLabel: String?, accessToken: String
    ) async throws -> StatementImportResult {
        let mappingData = try JSONEncoder().encode(mapping)
        guard let mappingText = String(data: mappingData, encoding: .utf8) else {
            throw FinMateAPIError.invalidResponse
        }
        var fields = ["accountName": accountName, "mapping": mappingText]
        if !categoryOverrides.isEmpty {
            let overrideData = try JSONEncoder().encode(categoryOverrides.mapKeys(String.init))
            fields["categoryOverrides"] = String(data: overrideData, encoding: .utf8) ?? "{}"
        }
        if let fingerprint { fields["fingerprint"] = fingerprint }
        if let bankLabel { fields["bankLabel"] = bankLabel }
        return try await sendMultipart(
            path: "/api/import/commit", fileData: fileData, fileName: fileName,
            fields: fields, accessToken: accessToken
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil
    ) async throws -> Response {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(cleanPath),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw FinMateAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FinMateAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
                ?? "The FinMate request failed."
            throw FinMateAPIError.server(statusCode: httpResponse.statusCode, message: message)
        }

        guard !data.isEmpty else { throw FinMateAPIError.emptyResponse }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func sendMultipart<Response: Decodable>(
        path: String, fileData: Data, fileName: String,
        fields: [String: String], accessToken: String
    ) async throws -> Response {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = Self.baseURL.appendingPathComponent(cleanPath)
        let boundary = "FinTrack-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            fileData: fileData, fileName: fileName, fields: fields, boundary: boundary
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw FinMateAPIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
                ?? "The FinMate request failed."
            throw FinMateAPIError.server(statusCode: httpResponse.statusCode, message: message)
        }
        guard !data.isEmpty else { throw FinMateAPIError.emptyResponse }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    static func multipartBody(
        fileData: Data, fileName: String, fields: [String: String], boundary: String
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(Data("--\(boundary)\(lineBreak)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)".utf8))
            body.append(Data("\(value)\(lineBreak)".utf8))
        }
        body.append(Data("--\(boundary)\(lineBreak)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(lineBreak)".utf8))
        body.append(Data("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)".utf8))
        body.append(fileData)
        body.append(Data(lineBreak.utf8))
        body.append(Data("--\(boundary)--\(lineBreak)".utf8))
        return body
    }
}

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let name: String
    let email: String
    let password: String
}

struct EmailExistsResponse: Decodable {
    let exists: Bool
}

struct ChangePasswordRequest: Encodable {
    let oldPassword: String
    let newPassword: String
}

struct TokenRequest: Encodable {
    let token: String
}

struct EmailRequest: Encodable {
    let email: String
}

struct ResetPasswordRequest: Encodable {
    let token: String
    let newPassword: String
}

struct AvatarRequest: Encodable {
    let avatar: String
}

struct AvatarResponse: Decodable {
    let ok: Bool
    let avatar: String
}

struct MonthlyEmailRequest: Encodable {
    let optIn: Bool
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct AuthUser: Codable, Equatable {
    let id: String
    let name: String
    let email: String
    let avatar: String?
}

struct AuthResponse: Decodable {
    let user: AuthUser
    let sessionId: String
    let accessToken: String
    let refreshToken: String
}

struct RefreshResponse: Decodable {
    let accessToken: String
}

struct VerificationResponse: Decodable {
    let status: String
}

struct LogoutResponse: Decodable {
    let ok: Bool
}

struct RemoteTransaction: Decodable {
    let id: String
    let name: String?
    let category: String?
    let date: String?
    let amount: Double?
    let account: String?
    let note: String?
    let currency: String?
}

struct RemoteTransactionRequest: Encodable {
    let name: String
    let category: String
    let date: String
    let amount: Double
    let account: String
    let note: String
    let currency: String

    init(transaction: FinanceTransaction, categoryName: String?) {
        name = transaction.merchant
        category = categoryName ?? ""
        date = Self.dateFormatter.string(from: transaction.occurredAt)
        let value = Double(transaction.amountMinor) / 100
        amount = transaction.kind.isInflow || transaction.kind == .refund ? abs(value) : -abs(value)
        account = transaction.paymentMethod
        note = transaction.note
        currency = transaction.currency
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct APIStatusResponse: Decodable {
    let ok: Bool
}

struct RemoteAccount: Decodable {
    let id: String
    let name: String?
    let type: String?
    let balance: Double?
    let limit: Double?
    let color: String?
    let bank: String?
}

struct RemoteGoal: Decodable {
    let id: String
    let name: String?
    let icon: String?
    let target: Double?
    let current: Double?
    let color: String?
    let deadline: String?
}

struct RemoteBill: Decodable {
    let id: String
    let name: String?
    let amount: Double?
    let dueDay: Int?
    let category: String?
    let color: String?
    let paid: Bool?
}

struct RemoteAccountRequest: Encodable {
    let name: String
    let type: String
    let balance: Double
    let limit: Double
    let color: String
    let bank: String

    init(account: FinanceAccount) {
        name = account.name
        type = account.type.rawValue
        balance = Double(account.balanceMinor) / 100
        limit = Double(account.limitMinor) / 100
        color = account.color
        bank = account.bank
    }
}

struct RemoteGoalRequest: Encodable {
    let name: String
    let icon: String
    let target: Double
    let current: Double
    let color: String
    let deadline: String

    init(goal: FinanceGoal) {
        name = goal.name
        icon = goal.icon
        target = Double(goal.targetMinor) / 100
        current = Double(goal.currentMinor) / 100
        color = goal.color
        deadline = goal.deadline
    }
}

struct RemoteBillRequest: Encodable {
    let name: String
    let amount: Double
    let dueDay: Int
    let category: String
    let color: String
    let paid: Bool

    init(bill: FinanceBill) {
        name = bill.name
        amount = Double(bill.amountMinor) / 100
        dueDay = bill.dueDay
        category = bill.category
        color = bill.color
        paid = bill.paid
    }
}

struct RemoteNotification: Decodable {
    let id: String
    let title: String?
    let body: String?
    let time: String?
    let read: Bool?
    let type: String?
}

struct RemoteNotificationRequest: Encodable {
    let title: String
    let body: String
    let time: String
    let read: Bool
    let type: String

    init(notification: FinanceNotification) {
        title = notification.title
        body = notification.body
        time = notification.time
        read = notification.read
        type = notification.type.rawValue
    }
}

struct RemoteSettings: Decodable {
    let name: String?
    let email: String?
    let currency: String?
    let notifs: [String: Bool]?
}

struct RemoteSettingsRequest: Encodable {
    let name: String
    let email: String
    let currency: String
    let notifs: [String: Bool]

    init(settings: FinanceUserSettings) {
        name = settings.name
        email = settings.email
        currency = settings.currency
        notifs = settings.notifications
    }
}

struct RemoteSession: Decodable, Identifiable, Equatable {
    let sessionId: String?
    let userId: String?
    let deviceLabel: String?
    let createdAt: String?
    let lastActiveAt: String?

    var id: String { sessionId ?? UUID().uuidString }
}

struct APIErrorResponse: Decodable {
    let error: String
}

struct RemoteChatUser: Decodable, Equatable {
    let id: String?
    let name: String?
    let email: String?
    let avatar: String?
    let lastActiveAt: String?

    var stableID: String { id ?? email ?? UUID().uuidString }
}

struct RemoteConversation: Decodable, Identifiable, Equatable {
    let id: String
    let lastMessage: String?
    let lastMessageAt: String?
}

struct RemoteMessage: Decodable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let body: String
    let sentAt: String
    let senderId: String
    let senderName: String
}

struct SendMessageRequest: Encodable {
    let conversationId: String
    let body: String
}

struct SendMessageResponse: Decodable, Equatable {
    let ok: Bool
    let id: String
}
