import Foundation

enum Money {
    static func minorUnits(from text: String) -> Int64? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty,
              let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0 else { return nil }
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled else { return nil }
        return Int64(NSDecimalNumber(decimal: rounded).stringValue)
    }

    static func formatted(_ minor: Int64, currency: String = "LKR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        let amount = NSDecimalNumber(value: minor).dividing(by: NSDecimalNumber(value: 100))
        return formatter.string(from: amount)
            ?? "\(currency) \(minor)"
    }
}

struct ReportTotals: Equatable {
    var incomeMinor: Int64 = 0
    var expenseMinor: Int64 = 0
    var netMinor: Int64 { incomeMinor - expenseMinor }
}

struct MerchantSpending: Identifiable {
    let name: String
    let amountMinor: Int64
    var id: String { name.lowercased() }
}

struct BudgetReport: Identifiable {
    let budget: FinanceBudget
    let spentMinor: Int64
    var id: UUID { budget.id }
    var remainingMinor: Int64 { budget.amountMinor - spentMinor }
}

struct RecurringPayment: Identifiable {
    let merchant: String
    let amountMinor: Int64
    let lastDate: Date
    var id: String { merchant.lowercased() }
}

enum FinanceMath {
    static func totals(for transactions: [FinanceTransaction], from start: Date, to end: Date) -> ReportTotals {
        transactions.reduce(into: ReportTotals()) { result, transaction in
            guard transaction.occurredAt >= start,
                  transaction.occurredAt < end else { return }
            if transaction.kind.isInflow {
                result.incomeMinor += transaction.amountMinor
            } else if transaction.kind.isOutflow {
                result.expenseMinor += transaction.amountMinor
            } else if transaction.kind == .refund {
                result.expenseMinor -= transaction.amountMinor
            }
        }
    }

    static func spending(for transactions: [FinanceTransaction], categoryID: UUID?, from start: Date, to end: Date) -> Int64 {
        transactions.reduce(into: Int64.zero) { total, transaction in
            guard transaction.occurredAt >= start,
                  transaction.occurredAt < end,
                  categoryID == nil || transaction.categoryID == categoryID else { return }
            if transaction.kind.isOutflow { total += transaction.amountMinor }
            if transaction.kind == .refund { total -= transaction.amountMinor }
        }
    }

    static func categorySpending(for transactions: [FinanceTransaction], from start: Date, to end: Date) -> [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for transaction in transactions where transaction.occurredAt >= start && transaction.occurredAt < end {
            guard let categoryID = transaction.categoryID else { continue }
            if transaction.kind.isOutflow { result[categoryID, default: 0] += transaction.amountMinor }
            if transaction.kind == .refund { result[categoryID, default: 0] -= transaction.amountMinor }
        }
        return result
    }

    static func merchantSpending(for transactions: [FinanceTransaction], from start: Date, to end: Date) -> [MerchantSpending] {
        var totals: [String: Int64] = [:]
        var names: [String: String] = [:]
        for transaction in transactions where transaction.occurredAt >= start && transaction.occurredAt < end {
            guard transaction.kind.isOutflow || transaction.kind == .refund else { continue }
            let name = transaction.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.isEmpty ? "unknown merchant" : name.lowercased()
            names[key] = name.isEmpty ? "Unknown merchant" : name
            totals[key, default: 0] += transaction.kind == .refund ? -transaction.amountMinor : transaction.amountMinor
        }
        return totals.compactMap { key, amount in
            amount > 0 ? MerchantSpending(name: names[key] ?? key, amountMinor: amount) : nil
        }
        .sorted { $0.amountMinor == $1.amountMinor ? $0.name < $1.name : $0.amountMinor > $1.amountMinor }
    }

    static func biggestSpends(for transactions: [FinanceTransaction], from start: Date, to end: Date) -> [FinanceTransaction] {
        transactions.filter {
            $0.occurredAt >= start && $0.occurredAt < end && $0.kind.isOutflow
        }
        .sorted { $0.amountMinor == $1.amountMinor ? $0.occurredAt > $1.occurredAt : $0.amountMinor > $1.amountMinor }
    }

    static func savingsPercentage(_ totals: ReportTotals) -> Double? {
        guard totals.incomeMinor > 0 else { return nil }
        return Double(totals.netMinor) / Double(totals.incomeMinor) * 100
    }

    static func budgetReports(
        for budgets: [FinanceBudget], transactions: [FinanceTransaction],
        from start: Date, to end: Date, calendar: Calendar = .current
    ) -> [BudgetReport] {
        budgets.compactMap { budget in
            guard let monthDate = calendar.date(from: DateComponents(
                year: Int(budget.month.prefix(4)) ?? 0,
                month: Int(budget.month.suffix(2)) ?? 0,
                day: 1
            )), let month = calendar.dateInterval(of: .month, for: monthDate),
                  month.start < end && month.end > start else { return nil }
            let spent = spending(for: transactions, categoryID: budget.categoryID, from: month.start, to: month.end)
            return BudgetReport(budget: budget, spentMinor: spent)
        }
        .sorted { $0.budget.month == $1.budget.month ? $0.budget.categoryID == nil : $0.budget.month > $1.budget.month }
    }

    static func recurringPayments(
        for transactions: [FinanceTransaction], from start: Date, to end: Date,
        calendar: Calendar = .current
    ) -> [RecurringPayment] {
        let expenses = transactions.filter {
            $0.kind.isOutflow && !$0.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let groups = Dictionary(grouping: expenses) { $0.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return groups.compactMap { _, payments -> RecurringPayment? in
            let sorted = payments.sorted { $0.occurredAt < $1.occurredAt }
            guard sorted.count >= 3, let latest = sorted.last,
                  latest.occurredAt >= start && latest.occurredAt < end else { return nil }
            let recent = Array(sorted.suffix(3))
            for index in 1..<recent.count {
                let previous = recent[index - 1]
                let current = recent[index]
                guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: previous.occurredAt),
                      abs(calendar.dateComponents([.day], from: nextMonth, to: current.occurredAt).day ?? 100) <= 7,
                      abs(Double(current.amountMinor) - Double(previous.amountMinor)) <= Double(previous.amountMinor) * 0.2
                else { return nil }
            }
            return RecurringPayment(merchant: latest.merchant, amountMinor: latest.amountMinor, lastDate: latest.occurredAt)
        }
        .sorted { $0.amountMinor > $1.amountMinor }
    }

    static func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, end: date)
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func budgetProgress(spentMinor: Int64, limitMinor: Int64) -> Double {
        guard limitMinor > 0 else { return 0 }
        return min(max(Double(spentMinor) / Double(limitMinor), 0), 1)
    }
}
