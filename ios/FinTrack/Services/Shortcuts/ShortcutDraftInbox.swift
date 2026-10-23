import Foundation

struct PendingShortcutDraft: Codable {
    let transaction: FinanceTransaction
    let reviewWarning: String?
}

@MainActor
final class PendingMessageReviewInbox {
    static let shared = PendingMessageReviewInbox()

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? appSupport.appendingPathComponent("FinTrack/message-reviews.json")
    }

    func all() -> [PendingShortcutDraft] {
        (try? read()) ?? []
    }

    func add(_ draft: PendingShortcutDraft) throws {
        var items = try read()
        if let reference = draft.transaction.externalReference,
           items.contains(where: { $0.transaction.externalReference == reference }) { return }
        items.append(draft)
        try write(items)
    }

    func remove(id: UUID) throws {
        try write(read().filter { $0.transaction.id != id })
    }

    private func read() throws -> [PendingShortcutDraft] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([PendingShortcutDraft].self, from: Data(contentsOf: fileURL))
    }

    private func write(_ items: [PendingShortcutDraft]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(items)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }
}

enum ShortcutDraftRoute: String {
    case messageImport = "import"
    case quickAdd = "add"
}

@MainActor
final class ShortcutDraftInbox {
    static let shared = ShortcutDraftInbox()

    private let fileURL: URL
    private let now: () -> Date

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? appSupport.appendingPathComponent("FinTrack/shortcut-draft.json")
        self.now = now
    }

    func enqueue(_ draft: PendingShortcutDraft, route: ShortcutDraftRoute) -> (id: UUID, url: URL)? {
        let id = UUID()
        var components = URLComponents()
        components.scheme = "fintrack"
        components.host = route.rawValue
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        guard let url = components.url else { return nil }

        let stored = StoredDraft(id: id, expiresAt: now().addingTimeInterval(600), draft: draft)
        guard let data = try? JSONEncoder().encode(stored) else { return nil }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
        } catch {
            return nil
        }
        return (id, url)
    }

    func take(id: UUID) -> PendingShortcutDraft? {
        guard let stored = readStored() else { return nil }
        if stored.expiresAt <= now() {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        guard stored.id == id else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return stored.pendingDraft
    }

    func discard(id: UUID) {
        if readStored()?.id == id { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func readStored() -> StoredDraft? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredDraft.self, from: data) else { return nil }
        return stored
    }

    private struct StoredDraft: Codable {
        let id: UUID
        let expiresAt: Date
        let transactionID: UUID
        let kind: String
        let amountMinor: Int64
        let occurredAt: Date
        let merchant: String
        let source: String
        let externalReference: String?
        let reviewWarning: String?

        init(id: UUID, expiresAt: Date, draft: PendingShortcutDraft) {
            self.id = id
            self.expiresAt = expiresAt
            transactionID = draft.transaction.id
            kind = draft.transaction.kind.rawValue
            amountMinor = draft.transaction.amountMinor
            occurredAt = draft.transaction.occurredAt
            merchant = draft.transaction.merchant
            source = draft.transaction.source.rawValue
            externalReference = draft.transaction.externalReference
            reviewWarning = draft.reviewWarning
        }

        var pendingDraft: PendingShortcutDraft? {
            guard let kind = TransactionKind(rawValue: kind),
                  let source = TransactionSource(rawValue: source),
                  amountMinor > 0 else { return nil }
            let transaction = FinanceTransaction(
                id: transactionID,
                kind: kind,
                amountMinor: amountMinor,
                occurredAt: occurredAt,
                merchant: merchant,
                source: source,
                externalReference: externalReference
            )
            return PendingShortcutDraft(transaction: transaction, reviewWarning: reviewWarning)
        }
    }
}
