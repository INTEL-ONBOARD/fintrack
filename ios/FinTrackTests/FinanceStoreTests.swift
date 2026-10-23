import Foundation
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
        currency: "LKR"
    )
    let synced = try #require(store.localTransaction(from: remote))
    try store.save(synced)

    let saved = try #require(store.transactions.first { $0.id == original.id })
    #expect(saved.latitude == 6.9271)
    #expect(saved.longitude == 79.8612)
    #expect(saved.locationName == "Colombo")
}
