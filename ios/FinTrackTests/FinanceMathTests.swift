import Foundation
import Testing
@testable import FinTrack

@Test func moneyParsesMinorUnitsWithoutRounding() {
    #expect(Money.minorUnits(from: "1,234.50") == 123_450)
    #expect(Money.minorUnits(from: "0.01") == 1)
    #expect(Money.minorUnits(from: "12.345") == nil)
    #expect(Money.minorUnits(from: "0") == nil)
}

@Test func reportUsesExclusiveEndAndExcludesTransfers() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(86_400)
    let transactions = [
        FinanceTransaction(kind: .income, amountMinor: 10_000, occurredAt: start),
        FinanceTransaction(kind: .expense, amountMinor: 4_000, occurredAt: start),
        FinanceTransaction(kind: .refund, amountMinor: 500, occurredAt: start),
        FinanceTransaction(kind: .transfer, amountMinor: 50_000, occurredAt: start),
        FinanceTransaction(kind: .cashWithdrawal, amountMinor: 2_000, occurredAt: start),
        FinanceTransaction(kind: .expense, amountMinor: 900, occurredAt: end)
    ]
    let totals = FinanceMath.totals(for: transactions, from: start, to: end)
    #expect(totals.incomeMinor == 10_000)
    #expect(totals.expenseMinor == 3_500)
    #expect(totals.netMinor == 6_500)
}

@Test func budgetSpendingTracksCategoryAndRefunds() {
    let categoryA = UUID()
    let categoryB = UUID()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(86_400)
    let transactions = [
        FinanceTransaction(kind: .expense, amountMinor: 5_000, occurredAt: start, categoryID: categoryA),
        FinanceTransaction(kind: .refund, amountMinor: 1_000, occurredAt: start, categoryID: categoryA),
        FinanceTransaction(kind: .expense, amountMinor: 3_000, occurredAt: start, categoryID: categoryB)
    ]
    #expect(FinanceMath.spending(for: transactions, categoryID: categoryA, from: start, to: end) == 4_000)
    #expect(FinanceMath.spending(for: transactions, categoryID: nil, from: start, to: end) == 7_000)
    #expect(FinanceMath.budgetProgress(spentMinor: 15_000, limitMinor: 10_000) == 1)
}
