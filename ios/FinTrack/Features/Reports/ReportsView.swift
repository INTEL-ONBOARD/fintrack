import Charts
import SwiftUI

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This week"
    case month = "This month"
    case lastMonth = "Last month"
    case year = "This year"
    case custom = "Custom"
    var id: String { rawValue }
}

private struct SpendingPoint: Identifiable {
    let date: Date
    let amountMinor: Int64
    var id: Date { date }
}

struct ReportsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selectedPeriod: ReportPeriod = .month
    @State private var customStart = Date.now
    @State private var customEnd = Date.now

    private var calendar: Calendar { .current }
    private var currency: String { store.settings.currency }
    private var transactions: [FinanceTransaction] {
        store.transactions.filter { $0.currency == currency }
    }

    private var interval: DateInterval {
        let now = Date.now
        switch selectedPeriod {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, end: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, end: now)
        case .month:
            return FinanceMath.monthInterval(containing: now)
        case .lastMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return FinanceMath.monthInterval(containing: previous)
        case .year:
            return calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, end: now)
        case .custom:
            let first = min(customStart, customEnd)
            let last = max(customStart, customEnd)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
            return DateInterval(start: calendar.startOfDay(for: first), end: end)
        }
    }

    private var totals: ReportTotals {
        FinanceMath.totals(for: transactions, from: interval.start, to: interval.end)
    }

    private var categories: [(name: String, amount: Int64)] {
        FinanceMath.categorySpending(for: transactions, from: interval.start, to: interval.end)
            .map { id, amount in
                (store.categories.first(where: { $0.id == id })?.name ?? "Uncategorized", amount)
            }
            .sorted { $0.amount > $1.amount }
    }

    private var merchants: [MerchantSpending] {
        FinanceMath.merchantSpending(for: transactions, from: interval.start, to: interval.end)
    }

    private var biggestSpends: [FinanceTransaction] {
        FinanceMath.biggestSpends(for: transactions, from: interval.start, to: interval.end)
    }

    private var recurring: [RecurringPayment] {
        FinanceMath.recurringPayments(for: transactions, from: interval.start, to: interval.end)
    }

    private var budgetReports: [BudgetReport] {
        FinanceMath.budgetReports(
            for: store.budgets.filter { $0.currency == currency },
            transactions: transactions, from: interval.start, to: interval.end
        )
    }

    private var spendingPoints: [SpendingPoint] {
        let component: Calendar.Component = selectedPeriod == .year ? .month : .day
        var date = interval.start
        var points: [SpendingPoint] = []
        while date < interval.end {
            guard let next = calendar.date(byAdding: component, value: 1, to: date) else { break }
            let end = min(next, interval.end)
            let amount = FinanceMath.spending(for: transactions, categoryID: nil, from: date, to: end)
            points.append(SpendingPoint(date: date, amountMinor: max(amount, 0)))
            date = end
        }
        return points
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                if selectedPeriod == .custom {
                    FinanceCard {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("Through", selection: $customEnd, displayedComponents: .date)
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    Text("\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(displayEnd.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Net cash flow")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(Money.formatted(totals.netMinor, currency: currency))
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    HStack {
                        metric("Income", amount: totals.incomeMinor, color: FinTrackStyle.green)
                        Spacer()
                        metric("Expenses", amount: totals.expenseMinor, color: .white)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FinTrackStyle.black, in: RoundedRectangle(cornerRadius: 28))

                FinanceCard {
                    Text("Spending trend").font(.headline)
                    if spendingPoints.allSatisfy({ $0.amountMinor == 0 }) {
                        Text("No spending in this period.").foregroundStyle(.secondary)
                    } else {
                        Chart(spendingPoints) { point in
                            BarMark(
                                x: .value("Date", point.date),
                                y: .value("Spending", Double(point.amountMinor) / 100)
                            )
                            .foregroundStyle(FinTrackStyle.black)
                        }
                        .frame(height: 170)
                        .accessibilityLabel("Spending trend. Total expenses \(Money.formatted(totals.expenseMinor, currency: currency)).")
                    }
                }

                FinanceCard {
                    Text("Top categories").font(.headline)
                    if categories.isEmpty {
                        Text("No categorized spending in this period.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(categories.prefix(5).enumerated()), id: \.offset) { _, category in
                            HStack {
                                Text(category.name)
                                Spacer()
                                Text(Money.formatted(category.amount, currency: currency))
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            Divider()
                        }
                    }
                }

                FinanceCard {
                    Text("Savings rate").font(.headline)
                    if let percentage = FinanceMath.savingsPercentage(totals) {
                        Text(percentage.formatted(.number.precision(.fractionLength(1))) + "%")
                            .font(.title2.bold())
                        Text("Net cash flow as a share of income.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add income to calculate your savings rate.").foregroundStyle(.secondary)
                    }
                }

                FinanceCard {
                    Text("Top merchants").font(.headline)
                    if merchants.isEmpty {
                        Text("No merchant spending in this period.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(merchants.prefix(5))) { merchant in
                            reportRow(merchant.name, amount: merchant.amountMinor)
                        }
                    }
                }

                FinanceCard {
                    Text("Biggest spends").font(.headline)
                    if biggestSpends.isEmpty {
                        Text("No expenses in this period.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(biggestSpends.prefix(5))) { transaction in
                            reportRow(
                                transaction.merchant.isEmpty ? transaction.kind.title : transaction.merchant,
                                detail: transaction.occurredAt.formatted(date: .abbreviated, time: .omitted),
                                amount: transaction.amountMinor
                            )
                        }
                    }
                }

                FinanceCard {
                    Text("Likely recurring payments").font(.headline)
                    if recurring.isEmpty {
                        Text("No monthly payment pattern found in this period.").foregroundStyle(.secondary)
                    } else {
                        ForEach(recurring) { payment in
                            reportRow(payment.merchant, detail: "Latest monthly payment", amount: payment.amountMinor)
                        }
                    }
                }

                FinanceCard {
                    Text("Budget performance").font(.headline)
                    Text("Full-month spending for each budget in this period.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if budgetReports.isEmpty {
                        Text("No budgets set for this period.").foregroundStyle(.secondary)
                    } else {
                        ForEach(budgetReports) { report in
                            let name = report.budget.categoryID.flatMap { id in
                                store.categories.first(where: { $0.id == id })?.name
                            } ?? "Overall"
                            let percent = report.budget.amountMinor > 0
                                ? Int(Double(report.spentMinor) / Double(report.budget.amountMinor) * 100)
                                : 0
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(name) · \(report.budget.month)")
                                    Spacer()
                                    Text("\(percent)%")
                                }
                                .font(.subheadline.weight(.medium))
                                ProgressView(value: FinanceMath.budgetProgress(
                                    spentMinor: report.spentMinor, limitMinor: report.budget.amountMinor
                                ))
                                Text("\(Money.formatted(report.spentMinor, currency: currency)) of \(Money.formatted(report.budget.amountMinor, currency: currency)) · \(Money.formatted(report.remainingMinor, currency: currency)) left")
                                    .font(.caption)
                                    .foregroundStyle(report.remainingMinor < 0 ? Color.red : Color.secondary)
                            }
                            Divider()
                        }
                    }
                }
            }
            .padding(FinTrackStyle.pageInset)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Reports")
    }

    private func metric(_ title: String, amount: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(Money.formatted(amount, currency: currency))
                .font(.headline)
                .foregroundStyle(color)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }

    private func reportRow(_ title: String, detail: String? = nil, amount: Int64) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(Money.formatted(amount, currency: currency))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }

    private var displayEnd: Date {
        calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    }
}
