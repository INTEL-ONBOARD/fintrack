import Foundation

enum RealtimeSyncEvent: Equatable {
    case transactions
    case goals
    case bills
    case accounts
    case notifications
    case settings
    case unknown

    init(serverEventName: String) {
        switch serverEventName.split(separator: ":").first.map(String.init) {
        case "transactions": self = .transactions
        case "goals": self = .goals
        case "bills": self = .bills
        case "accounts": self = .accounts
        case "notifications": self = .notifications
        case "settings": self = .settings
        default: self = .unknown
        }
    }
}

@MainActor
final class RealtimeSyncService: ObservableObject {
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var continuation: AsyncStream<RealtimeSyncEvent>.Continuation?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(accessToken: String) -> AsyncStream<RealtimeSyncEvent> {
        stop()
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
            self.start(accessToken: accessToken)
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        continuation?.finish()
        continuation = nil
    }

    private func start(accessToken: String) {
        guard var components = URLComponents(url: FinMateAPIClient.baseURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "wss"
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]
        guard let url = components.url else { return }
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveMessages(accessToken: accessToken)
        }
    }

    private func receiveMessages(accessToken: String) async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard case let .string(packet) = message else { continue }
                if packet.hasPrefix("0") {
                    try await socket.send(.string("40{\"token\":\"\(accessToken)\"}"))
                } else if packet == "2" {
                    try await socket.send(.string("3"))
                } else if let eventName = Self.eventName(from: packet) {
                    continuation?.yield(RealtimeSyncEvent(serverEventName: eventName))
                }
            }
        } catch {
            continuation?.finish()
        }
    }

    nonisolated static func eventName(from packet: String) -> String? {
        guard packet.hasPrefix("42"),
              let data = String(packet.dropFirst(2)).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let name = array.first as? String else { return nil }
        return name
    }
}
