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

struct SmartAlertPreferences {
    var budgetWarnings: Bool
    var recurringReminders: Bool
    var unusualSpending: Bool
    var showAmounts: Bool
}

struct SmartAlert: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date?
}

enum SmartAlertPlanner {
    static func make(
        now: Date, transactions: [FinanceTransaction], categories: [FinanceCategory],
        budgets: [FinanceBudget], currency: String, preferences: SmartAlertPreferences,
        calendar: Calendar = .current
    ) -> [SmartAlert] {
        let matching = transactions.filter { $0.currency == currency && $0.occurredAt <= now }
        var alerts: [SmartAlert] = []
        let month = FinanceMath.monthInterval(containing: now, calendar: calendar)

        if preferences.budgetWarnings {
            for budget in budgets where budget.currency == currency && budget.month == FinanceMath.monthKey(for: now, calendar: calendar) {
                let spent = FinanceMath.spending(
                    for: matching, categoryID: budget.categoryID, from: month.start, to: now.addingTimeInterval(1)
                )
                guard spent > 0, budget.amountMinor > 0,
                      Double(spent) >= Double(budget.amountMinor) * 0.8 else { continue }
                let exceeded = spent >= budget.amountMinor
                let name = budget.categoryID.flatMap { id in categories.first(where: { $0.id == id })?.name } ?? "overall"
                let body = preferences.showAmounts
                    ? "Your \(name) budget has used \(Money.formatted(spent, currency: currency)) of \(Money.formatted(budget.amountMinor, currency: currency))."
                    : "Your \(name) budget needs attention."
                alerts.append(SmartAlert(
                    id: "fintrack.smart.budget.\(budget.id).\(budget.month).\(exceeded ? 100 : 80)",
                    title: exceeded ? "Budget limit reached" : "Budget nearly used",
                    body: body, fireDate: nil
                ))
            }
        }

        if preferences.recurringReminders {
            let payments = FinanceMath.recurringPayments(
                for: matching, from: now.addingTimeInterval(-40 * 86_400), to: now.addingTimeInterval(1),
                calendar: calendar
            )
            for payment in payments.prefix(10) {
                guard let due = calendar.date(byAdding: .month, value: 1, to: payment.lastDate),
                      due > now, due < now.addingTimeInterval(35 * 86_400) else { continue }
                let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: due)) ?? due
                let preferred = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore) ?? dayBefore
                let dueMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
                let fireDate = preferred > now ? preferred : dueMorning
                guard fireDate > now else { continue }
                let body = preferences.showAmounts
                    ? "A payment to \(payment.merchant) of about \(Money.formatted(payment.amountMinor, currency: currency)) may be due soon."
                    : "A payment to \(payment.merchant) may be due soon."
                alerts.append(SmartAlert(
                    id: "fintrack.smart.recurring.\(payment.merchant.lowercased()).\(FinanceMath.monthKey(for: due, calendar: calendar))",
                    title: "Possible recurring payment", body: body, fireDate: fireDate
                ))
            }
        }

        if preferences.unusualSpending {
            let recent = matching.filter {
                $0.kind.isOutflow && $0.occurredAt >= now.addingTimeInterval(-86_400)
            }.sorted { $0.occurredAt > $1.occurredAt }
            for transaction in recent {
                let previous = matching.filter {
                    $0.kind.isOutflow && $0.id != transaction.id &&
                    $0.occurredAt < transaction.occurredAt &&
                    $0.occurredAt >= transaction.occurredAt.addingTimeInterval(-90 * 86_400)
                }.map(\.amountMinor).sorted()
                guard previous.count >= 5 else { continue }
                let median = previous[previous.count / 2]
                guard transaction.amountMinor >= 50_000,
                      Double(transaction.amountMinor) >= Double(median) * 3 else { continue }
                let body = preferences.showAmounts
                    ? "\(Money.formatted(transaction.amountMinor, currency: currency)) at \(transaction.merchant.isEmpty ? "an unknown merchant" : transaction.merchant) is much larger than your usual expenses."
                    : "A recent expense is much larger than your usual expenses."
                alerts.append(SmartAlert(
                    id: "fintrack.smart.unusual.\(transaction.id)",
                    title: "Unusual spending", body: body, fireDate: nil
                ))
                break
            }
        }
        return alerts
    }
}

@MainActor
enum LocalSmartNotificationScheduler {
    static let budgetKey = "smartBudgetWarningsEnabled"
    static let recurringKey = "smartRecurringRemindersEnabled"
    static let unusualKey = "smartUnusualSpendingEnabled"
    private static let sentKey = "fintrack.smart.sent-alerts"
    private static let alertPrefix = "fintrack.smart."

    static func preferences() -> SmartAlertPreferences {
        SmartAlertPreferences(
            budgetWarnings: UserDefaults.standard.bool(forKey: budgetKey),
            recurringReminders: UserDefaults.standard.bool(forKey: recurringKey),
            unusualSpending: UserDefaults.standard.bool(forKey: unusualKey),
            showAmounts: UserDefaults.standard.object(forKey: LocalSummaryNotificationScheduler.showAmountsKey) as? Bool ?? true
        )
    }

    static func schedule(
        transactions: [FinanceTransaction], categories: [FinanceCategory],
        budgets: [FinanceBudget], currency: String, now: Date = .now
    ) async {
        let center = UNUserNotificationCenter.current()
        let alerts = SmartAlertPlanner.make(
            now: now, transactions: transactions, categories: categories,
            budgets: budgets, currency: currency, preferences: preferences()
        )
        let desiredIDs = Set(alerts.map(\.id))
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(alertPrefix) && !desiredIDs.contains($0)
        })

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        var sent = (UserDefaults.standard.dictionary(forKey: sentKey) ?? [:]).compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        }
        sent = sent.filter { now.timeIntervalSince1970 - $0.value < 180 * 86_400 }

        for alert in alerts {
            if alert.fireDate == nil && sent[alert.id] != nil { continue }
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.userInfo = ["route": "reports"]
            let trigger: UNNotificationTrigger = alert.fireDate.map {
                UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: $0
                ), repeats: false)
            } ?? UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
            if alert.fireDate == nil {
                sent[alert.id] = now.timeIntervalSince1970
                UserDefaults.standard.set(sent, forKey: sentKey)
            }
            do {
                try await center.add(request)
            } catch {
                if alert.fireDate == nil {
                    sent.removeValue(forKey: alert.id)
                    UserDefaults.standard.set(sent, forKey: sentKey)
                }
            }
        }
        UserDefaults.standard.set(sent, forKey: sentKey)
    }
}
