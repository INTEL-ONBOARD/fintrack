import Foundation
import CoreData
import Testing
@testable import FinTrack

@Test @MainActor func usedCategoryCannotBeDeleted() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let category = try #require(store.categories.first { $0.kind == .expense })
    try store.save(FinanceTransaction(kind: .expense, amountMinor: 500, categoryID: category.id))

    do {
        try store.delete(category)
        Issue.record("Deleting a used category should fail")
    } catch FinanceStoreError.categoryInUse {
        #expect(store.categories.contains(where: { $0.id == category.id }))
    }
}

@Test @MainActor func monthlyBudgetScopeIsUnique() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    try store.save(FinanceBudget(month: "2026-10", amountMinor: 50_000))

    do {
        try store.save(FinanceBudget(month: "2026-10", amountMinor: 80_000))
        Issue.record("A second overall budget for the month should fail")
    } catch FinanceStoreError.duplicateBudget {
        #expect(store.budgets.count == 1)
    }
}

@Test @MainActor func importedMessageCannotBeSavedTwice() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let first = FinanceTransaction(
        kind: .expense, amountMinor: 1_250, source: .sms,
        externalReference: "sms:sample-message"
    )
    try store.save(first)

    do {
        try store.save(FinanceTransaction(
            kind: .expense, amountMinor: 1_250, source: .sms,
            externalReference: "sms:sample-message"
        ))
        Issue.record("The same message should not be saved twice")
    } catch FinanceStoreError.duplicateImport {
        #expect(store.transactions.count == 1)
    }
}

@Test @MainActor func syncingTransactionKeepsLocalLocation() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let original = FinanceTransaction(
        kind: .expense,
        amountMinor: 1_000,
        merchant: "Shop",
        externalReference: "api:transaction-123",
        latitude: 6.9271,
        longitude: 79.8612,
        locationName: "Colombo"
    )
    try store.save(original)

    let remote = RemoteTransaction(
        id: "transaction-123",
        name: "Shop",
        category: nil,
        date: "2026-10-23",
        amount: -10,
        account: nil,
        note: nil,
        currency: "LKR",
        hasReceipt: nil
    )
    let synced = try #require(store.localTransaction(from: remote))
    try store.save(synced)

    let saved = try #require(store.transactions.first { $0.id == original.id })
    #expect(saved.latitude == 6.9271)
    #expect(saved.longitude == 79.8612)
    #expect(saved.locationName == "Colombo")
}

@Test @MainActor func receiptSurvivesEditAndIsRemovedWithTransaction() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let original = FinanceTransaction(kind: .expense, amountMinor: 1_500, source: .receipt)
    let image = Data([0xFF, 0xD8, 0xFF, 0xD9])
    try store.save(original, receiptImageData: image)
    #expect(store.receiptImageData(for: original.id) == image)

    var edited = original
    edited.merchant = "Cafe"
    try store.save(edited)
    #expect(store.receiptImageData(for: original.id) == image)

    try store.delete(edited)
    #expect(store.receiptImageData(for: original.id) == nil)
}

@Test @MainActor func receiptRejectsOversizedImageWithoutSavingTransaction() throws {
    let store = FinanceStore(persistence: PersistenceController(inMemory: true))
    let transaction = FinanceTransaction(kind: .expense, amountMinor: 1_500)
    do {
        try store.save(transaction, receiptImageData: Data(count: 2_000_001))
        Issue.record("An oversized receipt should not be saved")
    } catch FinanceStoreError.invalidReceiptImage {
        #expect(!store.transactions.contains(where: { $0.id == transaction.id }))
    }
}

@Test func widgetQuickAddLinksOnlyOpenExpenseOrIncome() {
    #expect(WidgetQuickAddLink.kind(from: URL(string: "fintrack://quick-add?kind=expense")!) == .expense)
    #expect(WidgetQuickAddLink.kind(from: URL(string: "fintrack://quick-add?kind=income")!) == .income)
    #expect(WidgetQuickAddLink.kind(from: URL(string: "fintrack://quick-add?kind=transfer")!) == nil)
    #expect(WidgetQuickAddLink.kind(from: URL(string: "fintrack://quick-add?kind=expense&amount=1")!) == nil)
}

@Test @MainActor func syncedCategoryDeletionKeepsAnOfflineDeleteRequest() throws {
    let persistence = PersistenceController(inMemory: true)
    let store = FinanceStore(persistence: persistence)
    let category = FinanceCategory(serverID: "category-7", name: "Travel test", kind: .expense)
    try store.save(category, fromServer: true)
    try store.delete(category)

    let request = NSFetchRequest<PendingDeletionEntity>(entityName: "PendingDeletion")
    let pending = try persistence.container.viewContext.fetch(request)
    #expect(pending.count == 1)
    #expect(pending.first?.resource == "categories")
    #expect(pending.first?.serverID == "category-7")
}

@Test func overallBudgetRequestIncludesNullCategory() throws {
    let budget = FinanceBudget(month: "2026-10", amountMinor: 75_000)
    let data = try JSONEncoder().encode(RemoteBudgetRequest(budget: budget, categoryServerID: nil))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["categoryId"] is NSNull)
    #expect(json["amountMinor"] as? Int == 75_000)
}

@Test @MainActor func categoryIsUploadedBeforeItsBudget() async throws {
    let calls = SyncRequestLog()
    SyncURLProtocol.handler = { request in
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? ""
        let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        calls.append("\(method) \(path)", body: body)
        if method == "GET" { return (200, Data("[]".utf8)) }
        if method == "POST", path.hasSuffix("/api/categories") {
            var response = body
            response["id"] = "cat-\(body["clientId"] ?? "missing")"
            return (201, try! JSONSerialization.data(withJSONObject: response))
        }
        if method == "POST", path.hasSuffix("/api/budgets") {
            var response = body
            response["id"] = "budget-1"
            return (201, try! JSONSerialization.data(withJSONObject: response))
        }
        return (404, Data("{\"error\":\"missing route\"}".utf8))
    }
    defer { SyncURLProtocol.handler = nil }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SyncURLProtocol.self]
    let api = FinMateAPIClient(session: URLSession(configuration: config), apiURL: URL(string: "https://sync.test/finwise")!)
    let store = FinanceStore(persistence: PersistenceController(inMemory: true), api: api)
    let category = FinanceCategory(name: "Trip", kind: .expense)
    let budget = FinanceBudget(month: "2026-10", categoryID: category.id, amountMinor: 12_500)
    try store.save(category)
    try store.save(budget)

    await store.syncCategoriesBudgets(accessToken: "test-token")

    #expect(store.errorMessage == nil)
    let savedCategory = try #require(store.categories.first { $0.id == category.id })
    let savedBudget = try #require(store.budgets.first { $0.id == budget.id })
    #expect(savedCategory.serverID != nil && !savedCategory.needsSync)
    #expect(savedBudget.serverID == "budget-1" && !savedBudget.needsSync)
    let savedCalls = calls.entries
    let budgetPost = try #require(savedCalls.firstIndex { $0.path == "POST /finwise/api/budgets" })
    let categoryPost = try #require(savedCalls.firstIndex { $0.path == "POST /finwise/api/categories" })
    #expect(categoryPost < budgetPost)
    #expect(savedCalls[budgetPost].body["categoryId"] as? String == savedCategory.serverID)
    #expect(savedCalls[budgetPost].body["amountMinor"] as? Int == 12_500)
}

private final class SyncRequestLog {
    private let lock = NSLock()
    private var values: [(path: String, body: [String: Any])] = []

    func append(_ path: String, body: [String: Any]) {
        lock.lock()
        values.append((path, body))
        lock.unlock()
    }

    var entries: [(path: String, body: [String: Any])] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class SyncURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
