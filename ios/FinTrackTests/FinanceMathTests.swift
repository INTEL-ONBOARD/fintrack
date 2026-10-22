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

@Test func localMonthlySummaryIncludesTotalsTopCategoryAndBudget() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
    let groceries = FinanceCategory(name: "Groceries", kind: .expense)
    let transactions = [
        FinanceTransaction(kind: .income, amountMinor: 100_000, occurredAt: date),
        FinanceTransaction(kind: .expense, amountMinor: 20_000, occurredAt: date, categoryID: groceries.id),
        FinanceTransaction(kind: .refund, amountMinor: 2_000, occurredAt: date, categoryID: groceries.id)
    ]
    let budgets = [FinanceBudget(month: "2026-10", amountMinor: 50_000)]

    let summary = LocalSummaryReportBuilder.make(
        for: date,
        transactions: transactions,
        categories: [groceries],
        budgets: budgets,
        currency: "LKR",
        calendar: calendar
    )

    #expect(summary.monthKey == "2026-10")
    #expect(summary.transactionCount == 3)
    #expect(summary.totals.incomeMinor == 100_000)
    #expect(summary.totals.expenseMinor == 18_000)
    #expect(summary.topCategoryName == "Groceries")
    #expect(summary.topCategoryMinor == 18_000)
    #expect(summary.budgetLimitMinor == 50_000)
    #expect(summary.budgetSpentMinor == 18_000)
}

@Test func localSummaryNotificationCanHideAmounts() {
    let summary = LocalMonthlySummary(
        monthKey: "2026-10",
        monthTitle: "October 2026",
        transactionCount: 1,
        totals: ReportTotals(incomeMinor: 100_000, expenseMinor: 20_000),
        topCategoryName: "Groceries",
        topCategoryMinor: 20_000,
        budgetLimitMinor: nil,
        budgetSpentMinor: 20_000,
        currency: "LKR"
    )

    #expect(summary.notificationBody(showAmounts: true).contains("LKR"))
    #expect(!summary.notificationBody(showAmounts: false).contains("100,000"))
    #expect(summary.notificationBody(showAmounts: false).contains("Groceries"))
}

@Test func monthlySpendingIntentIncludesTotalAndTopCategory() {
    let summary = LocalMonthlySummary(
        monthKey: "2026-10",
        monthTitle: "October 2026",
        transactionCount: 2,
        totals: ReportTotals(incomeMinor: 100_000, expenseMinor: 18_000),
        topCategoryName: "Groceries",
        topCategoryMinor: 18_000,
        budgetLimitMinor: 50_000,
        budgetSpentMinor: 18_000,
        currency: "LKR"
    )

    let text = FinancialSummaryIntentText.monthlySpending(for: summary)
    #expect(text.contains("LKR"))
    #expect(text.contains("Groceries"))
}

@Test func budgetStatusIntentHandlesRemainingAndOverBudget() {
    let withinBudget = LocalMonthlySummary(
        monthKey: "2026-10", monthTitle: "October 2026", transactionCount: 1,
        totals: ReportTotals(expenseMinor: 18_000), topCategoryName: nil,
        topCategoryMinor: 0, budgetLimitMinor: 50_000, budgetSpentMinor: 18_000,
        currency: "LKR"
    )
    let overBudget = LocalMonthlySummary(
        monthKey: "2026-10", monthTitle: "October 2026", transactionCount: 1,
        totals: ReportTotals(expenseMinor: 60_000), topCategoryName: nil,
        topCategoryMinor: 0, budgetLimitMinor: 50_000, budgetSpentMinor: 60_000,
        currency: "LKR"
    )

    #expect(FinancialSummaryIntentText.budgetStatus(for: withinBudget).contains("36%"))
    #expect(FinancialSummaryIntentText.budgetStatus(for: withinBudget).contains("LKR"))
    #expect(FinancialSummaryIntentText.budgetStatus(for: overBudget).contains("over the limit"))
}

@Test func onDeviceClassifierSuggestsCategoryFromMerchantText() {
    let groceries = FinanceCategory(name: "Groceries", kind: .expense)
    let transport = FinanceCategory(name: "Transport", kind: .expense)

    let result = OnDeviceTransactionClassifier(model: nil).suggest(
        text: "Keells supermarket groceries",
        kind: .expense,
        categories: [groceries, transport]
    )

    #expect(result?.categoryID == groceries.id)
    #expect(result?.categoryName == "Groceries")
    #expect(result?.source == .rules)
    #expect(result?.languageCode != nil)
}

@Test func classifierFeedbackStoresOnlyCorrections() {
    OnDeviceClassifierFeedback.clear()
    let groceries = FinanceCategory(name: "Groceries", kind: .expense)
    let transport = FinanceCategory(name: "Transport", kind: .expense)
    let suggestion = OnDeviceClassificationResult(
        categoryID: groceries.id,
        categoryName: groceries.name,
        confidence: 0.7,
        languageCode: "en",
        source: .rules
    )

    OnDeviceClassifierFeedback.record(text: "taxi ride", suggestion: suggestion, chosenCategory: transport)
    #expect(OnDeviceClassifierFeedback.load().count == 1)
    #expect(OnDeviceClassifierFeedback.load().first?.chosenCategory == "Transport")

    OnDeviceClassifierFeedback.record(text: "groceries", suggestion: suggestion, chosenCategory: groceries)
    #expect(OnDeviceClassifierFeedback.load().count == 1)
    OnDeviceClassifierFeedback.clear()
}
