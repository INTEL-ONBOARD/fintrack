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

@Test func reportSummariesHandleRefundsAndMissingIncome() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(86_400)
    let transactions = [
        FinanceTransaction(kind: .income, amountMinor: 20_000, occurredAt: start),
        FinanceTransaction(kind: .expense, amountMinor: 8_000, occurredAt: start, merchant: "Cafe"),
        FinanceTransaction(kind: .expense, amountMinor: 3_000, occurredAt: start, merchant: " cafe "),
        FinanceTransaction(kind: .refund, amountMinor: 1_000, occurredAt: start, merchant: "Cafe"),
        FinanceTransaction(kind: .transfer, amountMinor: 50_000, occurredAt: start, merchant: "Cafe"),
        FinanceTransaction(kind: .expense, amountMinor: 5_000, occurredAt: end, merchant: "Other")
    ]
    let merchants = FinanceMath.merchantSpending(for: transactions, from: start, to: end)
    let biggest = FinanceMath.biggestSpends(for: transactions, from: start, to: end)
    #expect(merchants.count == 1)
    #expect(merchants.first?.amountMinor == 10_000)
    #expect(biggest.map(\.amountMinor) == [8_000, 3_000])
    #expect(FinanceMath.savingsPercentage(FinanceMath.totals(for: transactions, from: start, to: end)) == 50)
    #expect(FinanceMath.savingsPercentage(ReportTotals(expenseMinor: 1_000)) == nil)
}

@Test func budgetReportUsesWholeMonthAndCategory() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    let middle = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
    let last = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
    let category = UUID()
    let budget = FinanceBudget(month: "2026-10", categoryID: category, amountMinor: 10_000)
    let transactions = [
        FinanceTransaction(kind: .expense, amountMinor: 5_000, occurredAt: first, categoryID: category),
        FinanceTransaction(kind: .expense, amountMinor: 7_000, occurredAt: last, categoryID: category),
        FinanceTransaction(kind: .expense, amountMinor: 9_000, occurredAt: middle, categoryID: UUID())
    ]
    let reports = FinanceMath.budgetReports(
        for: [budget], transactions: transactions,
        from: middle, to: middle.addingTimeInterval(86_400), calendar: calendar
    )
    #expect(reports.count == 1)
    #expect(reports.first?.spentMinor == 12_000)
    #expect(reports.first?.remainingMinor == -2_000)
}

@Test func recurringPaymentsNeedThreeSimilarMonthlyCharges() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    let transactions = [
        FinanceTransaction(kind: .expense, amountMinor: 1_000, occurredAt: date(8, 10), merchant: "Streaming"),
        FinanceTransaction(kind: .expense, amountMinor: 1_050, occurredAt: date(9, 11), merchant: "streaming"),
        FinanceTransaction(kind: .expense, amountMinor: 1_000, occurredAt: date(10, 10), merchant: "Streaming"),
        FinanceTransaction(kind: .expense, amountMinor: 3_000, occurredAt: date(8, 1), merchant: "Store"),
        FinanceTransaction(kind: .expense, amountMinor: 1_000, occurredAt: date(9, 1), merchant: "Store"),
        FinanceTransaction(kind: .expense, amountMinor: 4_000, occurredAt: date(10, 1), merchant: "Store")
    ]
    let matches = FinanceMath.recurringPayments(
        for: transactions, from: date(10, 1), to: date(11, 1), calendar: calendar
    )
    #expect(matches.count == 1)
    #expect(matches.first?.merchant == "Streaming")
    #expect(FinanceMath.recurringPayments(
        for: transactions, from: date(11, 1), to: date(12, 1), calendar: calendar
    ).isEmpty)
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

@Test func onDeviceInsightsWarnAboutProjectedBudgetAndDominantCategory() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
    let groceries = FinanceCategory(name: "Groceries", kind: .expense)
    let transactions = [
        FinanceTransaction(kind: .expense, amountMinor: 50_000, occurredAt: date, categoryID: groceries.id),
        FinanceTransaction(kind: .expense, amountMinor: 10_000, occurredAt: date, categoryID: UUID()),
        FinanceTransaction(
            kind: .expense,
            amountMinor: 30_000,
            occurredAt: calendar.date(byAdding: .month, value: -1, to: date)!,
            categoryID: groceries.id
        )
    ]
    let budgets = [FinanceBudget(month: "2026-10", amountMinor: 100_000)]

    let insights = OnDeviceInsights.make(
        for: date,
        transactions: transactions,
        categories: [groceries],
        budgets: budgets,
        calendar: calendar
    )

    #expect(insights.contains { $0.id == "projected-budget-overrun" })
    #expect(insights.contains { $0.id == "spending-increase" })
    #expect(insights.contains { $0.message.contains("Groceries") })
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
