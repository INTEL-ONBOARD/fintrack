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

struct APIErrorResponse: Decodable {
    let error: String
}
