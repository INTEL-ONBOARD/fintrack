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
