import Foundation
import UserNotifications

struct LocalMonthlySummary: Equatable {
    let monthKey: String
    let monthTitle: String
    let transactionCount: Int
    let totals: ReportTotals
    let topCategoryName: String?
    let topCategoryMinor: Int64
    let budgetLimitMinor: Int64?
    let budgetSpentMinor: Int64
    let currency: String

    var budgetProgress: Double? {
        guard let budgetLimitMinor, budgetLimitMinor > 0 else { return nil }
        return FinanceMath.budgetProgress(spentMinor: budgetSpentMinor, limitMinor: budgetLimitMinor)
    }

    func notificationBody(showAmounts: Bool) -> String {
        var parts: [String] = []
        if showAmounts {
            parts.append("Income \(Money.formatted(totals.incomeMinor, currency: currency))")
            parts.append("expenses \(Money.formatted(totals.expenseMinor, currency: currency))")
            parts.append("net \(Money.formatted(totals.netMinor, currency: currency))")
        } else {
            parts.append("Your income and expense totals are ready")
        }

        if let topCategoryName {
            if showAmounts {
                parts.append("top category \(topCategoryName) \(Money.formatted(topCategoryMinor, currency: currency))")
            } else {
                parts.append("top category \(topCategoryName)")
            }
        }

        if let budgetProgress {
            parts.append("budget \(Int(budgetProgress * 100))% used")
        }

        return parts.joined(separator: " · ") + "."
    }
}

enum LocalSummaryReportBuilder {
    static func make(
        for date: Date,
        transactions: [FinanceTransaction],
        categories: [FinanceCategory],
        budgets: [FinanceBudget],
        currency: String,
        calendar: Calendar = .current
    ) -> LocalMonthlySummary {
        let interval = FinanceMath.monthInterval(containing: date, calendar: calendar)
        let monthKey = FinanceMath.monthKey(for: date, calendar: calendar)
        let periodTransactions = transactions.filter {
            $0.occurredAt >= interval.start && $0.occurredAt < interval.end
        }
        let totals = FinanceMath.totals(
            for: transactions,
            from: interval.start,
            to: interval.end
        )
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let topCategory = FinanceMath.categorySpending(
            for: transactions,
            from: interval.start,
            to: interval.end
        )
        .filter { $0.value > 0 }
        .max { $0.value < $1.value }

        let budget = budgets.first {
            $0.month == monthKey && $0.categoryID == nil
        }
        let budgetSpent = FinanceMath.spending(
            for: transactions,
            categoryID: nil,
            from: interval.start,
            to: interval.end
        )

        return LocalMonthlySummary(
            monthKey: monthKey,
            monthTitle: interval.start.formatted(.dateTime.month(.wide).year()),
            transactionCount: periodTransactions.count,
            totals: totals,
            topCategoryName: topCategory.flatMap { categoryNames[$0.key] },
            topCategoryMinor: topCategory?.value ?? 0,
            budgetLimitMinor: budget?.amountMinor,
            budgetSpentMinor: budgetSpent,
            currency: currency
        )
    }
}

enum LocalSummaryNotificationScheduler {
    static let enabledKey = "localSummaryNotificationsEnabled"
    static let showAmountsKey = "localSummaryNotificationShowAmounts"
    private static let notificationIdentifier = "fintrack.local-monthly-summary"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func scheduleCurrentMonthSummary(
        transactions: [FinanceTransaction],
        categories: [FinanceCategory],
        budgets: [FinanceBudget],
        currency: String
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let settings = await notificationSettings(center: center)
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let summary = LocalSummaryReportBuilder.make(
            for: .now,
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            currency: currency
        )
        guard summary.transactionCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "FinTrack monthly summary"
        content.body = summary.notificationBody(
            showAmounts: UserDefaults.standard.object(forKey: showAmountsKey) as? Bool ?? true
        )
        content.sound = .default
        content.userInfo = ["route": "reports", "month": summary.monthKey]

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(86_400)
        let components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        var triggerComponents = DateComponents()
        triggerComponents.year = components.year
        triggerComponents.month = components.month
        triggerComponents.day = components.day
        triggerComponents.hour = 9
        triggerComponents.minute = 0

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        )
        await add(request, to: center)
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    private static func notificationSettings(center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }
}
