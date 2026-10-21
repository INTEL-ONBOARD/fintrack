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

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        accessToken: String? = nil
    ) async throws -> Response {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = Self.baseURL.appendingPathComponent(cleanPath)

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

struct APIErrorResponse: Decodable {
    let error: String
}
