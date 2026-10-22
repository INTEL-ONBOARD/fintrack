import Foundation
import WidgetKit

enum WidgetSnapshotWriter {
    @MainActor
    static func update(
        transactions: [FinanceTransaction],
        budgets: [FinanceBudget],
        settings: FinanceUserSettings,
        date: Date = .now
    ) {
        let month = FinanceMath.monthInterval(containing: date)
        let totals = FinanceMath.totals(for: transactions, from: month.start, to: month.end)
        let monthKey = FinanceMath.monthKey(for: date)
        let budgetLimit = budgets
            .filter { $0.month == monthKey && $0.categoryID == nil }
            .reduce(Int64.zero) { $0 + $1.amountMinor }
        let remaining = budgetLimit > 0 ? max(0, budgetLimit - totals.expenseMinor) : nil
        let snapshot = WidgetSummarySnapshot(
            incomeMinor: totals.incomeMinor,
            expenseMinor: totals.expenseMinor,
            budgetRemainingMinor: remaining,
            currency: settings.currency,
            updatedAt: date
        )
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
