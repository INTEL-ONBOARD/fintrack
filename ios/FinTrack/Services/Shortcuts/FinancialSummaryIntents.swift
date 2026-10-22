import AppIntents
import Foundation

enum FinancialSummaryIntentText {
    static func monthlySpending(for summary: LocalMonthlySummary) -> String {
        var text = "You spent \(Money.formatted(summary.totals.expenseMinor, currency: summary.currency)) in \(summary.monthTitle)."
        if let category = summary.topCategoryName {
            text += " Your top category was \(category), at \(Money.formatted(summary.topCategoryMinor, currency: summary.currency))."
        }
        return text
    }

    static func budgetStatus(for summary: LocalMonthlySummary) -> String {
        guard let limit = summary.budgetLimitMinor, limit > 0 else {
            return "You do not have an overall budget set for \(summary.monthTitle)."
        }

        let spent = summary.budgetSpentMinor
        if spent > limit {
            let over = spent - limit
            return "You used \(Money.formatted(spent, currency: summary.currency)) of your budget and are \(Money.formatted(over, currency: summary.currency)) over the limit."
        }

        let remaining = limit - spent
        let percent = Int((Double(spent) / Double(limit) * 100).rounded())
        return "You used \(percent)% of your budget. \(Money.formatted(remaining, currency: summary.currency)) remains."
    }
}

struct MonthlySpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "Monthly Spending"
    static let description = IntentDescription("Read this month's local spending summary in FinTrack.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinanceStore()
        let summary = LocalSummaryReportBuilder.make(
            for: .now,
            transactions: store.transactions,
            categories: store.categories,
            budgets: store.budgets,
            currency: store.settings.currency
        )
        return .result(dialog: "\(FinancialSummaryIntentText.monthlySpending(for: summary))")
    }
}

struct BudgetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Budget Status"
    static let description = IntentDescription("Read this month's local budget status in FinTrack.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinanceStore()
        let summary = LocalSummaryReportBuilder.make(
            for: .now,
            transactions: store.transactions,
            categories: store.categories,
            budgets: store.budgets,
            currency: store.settings.currency
        )
        return .result(dialog: "\(FinancialSummaryIntentText.budgetStatus(for: summary))")
    }
}
