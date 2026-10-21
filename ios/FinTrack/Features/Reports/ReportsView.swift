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
        FinanceMath.totals(for: store.transactions, from: interval.start, to: interval.end)
    }

    private var categories: [(name: String, amount: Int64)] {
        FinanceMath.categorySpending(for: store.transactions, from: interval.start, to: interval.end)
            .map { id, amount in
                (store.categories.first(where: { $0.id == id })?.name ?? "Uncategorized", amount)
            }
            .sorted { $0.amount > $1.amount }
    }

    private var spendingPoints: [SpendingPoint] {
        let component: Calendar.Component = selectedPeriod == .year ? .month : .day
        var date = interval.start
        var points: [SpendingPoint] = []
        while date < interval.end {
            guard let next = calendar.date(byAdding: component, value: 1, to: date) else { break }
            let end = min(next, interval.end)
            let amount = FinanceMath.spending(for: store.transactions, categoryID: nil, from: date, to: end)
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

                FinanceCard {
                    Text("\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(displayEnd.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        metric("Income", amount: totals.incomeMinor, color: FinTrackStyle.green)
                        Spacer()
                        metric("Expenses", amount: totals.expenseMinor, color: FinTrackStyle.ink)
                    }
                    Divider()
                    metric("Net cash flow", amount: totals.netMinor, color: FinTrackStyle.purple)
                }

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
                            .foregroundStyle(FinTrackStyle.purple)
                        }
                        .frame(height: 170)
                        .accessibilityLabel("Spending trend. Total expenses \(Money.formatted(totals.expenseMinor)).")
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
                                Text(Money.formatted(category.amount))
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Reports")
    }

    private func metric(_ title: String, amount: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.formatted(amount))
                .font(.headline)
                .foregroundStyle(color)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }

    private var displayEnd: Date {
        calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    }
}
