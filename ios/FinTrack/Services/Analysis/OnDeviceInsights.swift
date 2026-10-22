import Foundation

enum OnDeviceInsightLevel: Equatable {
    case positive
    case warning
    case information
}

struct OnDeviceInsight: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let level: OnDeviceInsightLevel
}

enum OnDeviceInsights {
    static func make(
        for date: Date,
        transactions: [FinanceTransaction],
        categories: [FinanceCategory],
        budgets: [FinanceBudget],
        calendar: Calendar = .current
    ) -> [OnDeviceInsight] {
        let month = FinanceMath.monthInterval(containing: date, calendar: calendar)
        let monthKey = FinanceMath.monthKey(for: date, calendar: calendar)
        let endOfCurrentDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date
        let currentEnd = min(endOfCurrentDay, month.end)
        guard currentEnd > month.start else { return [] }

        let currentSpending = FinanceMath.spending(
            for: transactions, categoryID: nil, from: month.start, to: currentEnd
        )
        let previousDate = calendar.date(byAdding: .month, value: -1, to: date) ?? date
        let previousMonth = FinanceMath.monthInterval(containing: previousDate, calendar: calendar)
        let previousSpending = FinanceMath.spending(
            for: transactions, categoryID: nil, from: previousMonth.start, to: previousMonth.end
        )

        var insights: [OnDeviceInsight] = []

        let elapsedDays = max(
            1,
            (calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: month.start),
                to: calendar.startOfDay(for: date)
            ).day ?? 0) + 1
        )
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let projectedSpending = Int64(
            (Double(currentSpending) / Double(elapsedDays) * Double(daysInMonth)).rounded()
        )

        if let budget = budgets.first(where: { $0.month == monthKey && $0.categoryID == nil }),
           projectedSpending > budget.amountMinor {
            let expectedOverrun = projectedSpending - budget.amountMinor
            insights.append(OnDeviceInsight(
                id: "projected-budget-overrun",
                title: "Budget warning",
                message: "At this pace, you may exceed your budget by \(Money.formatted(expectedOverrun, currency: budget.currency)).",
                level: .warning
            ))
        }

        if previousSpending > 0 {
            let change = Double(currentSpending - previousSpending) / Double(previousSpending)
            let percent = Int(abs(change * 100).rounded())
            if change >= 0.2 {
                insights.append(OnDeviceInsight(
                    id: "spending-increase",
                    title: "Spending is up",
                    message: "Your spending is \(percent)% higher than last month so far.",
                    level: .warning
                ))
            } else if change <= -0.2 {
                insights.append(OnDeviceInsight(
                    id: "spending-decrease",
                    title: "Spending is lower",
                    message: "Your spending is \(percent)% lower than last month so far.",
                    level: .positive
                ))
            }
        }

        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        if let topCategory = FinanceMath.categorySpending(
            for: transactions, from: month.start, to: currentEnd
        )
        .filter({ $0.value > 0 })
        .max(by: { $0.value < $1.value }),
           currentSpending > 0,
           Double(topCategory.value) / Double(currentSpending) >= 0.4 {
            let name = categoryNames[topCategory.key] ?? "One category"
            insights.append(OnDeviceInsight(
                id: "dominant-category",
                title: "Category to watch",
                message: "\(name) makes up \(Int((Double(topCategory.value) / Double(currentSpending) * 100).rounded()))% of this month's spending.",
                level: .information
            ))
        }

        return insights
    }
}
