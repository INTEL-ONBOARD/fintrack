import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var showingEditor = false

    private var period: DateInterval { FinanceMath.monthInterval(containing: .now) }
    private var totals: ReportTotals {
        FinanceMath.totals(for: store.transactions, from: period.start, to: period.end)
    }
    private var overallBudget: FinanceBudget? {
        store.budgets.first { $0.month == FinanceMath.monthKey(for: .now) && $0.categoryID == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Here’s your money overview")
                        .font(.title2.bold())
                        .foregroundStyle(FinTrackStyle.ink)
                }

                FinanceCard {
                    HStack(alignment: .top) {
                        summaryItem("Income", amount: totals.incomeMinor, color: FinTrackStyle.green)
                        Spacer()
                        summaryItem("Expenses", amount: totals.expenseMinor, color: FinTrackStyle.ink)
                    }
                    Divider().padding(.vertical, 8)
                    Text("Net cash flow").font(.caption).foregroundStyle(.secondary)
                    Text(Money.formatted(totals.netMinor))
                        .font(.title3.bold())
                        .foregroundStyle(totals.netMinor >= 0 ? FinTrackStyle.purple : FinTrackStyle.ink)
                }

                NavigationLink {
                    BudgetsView()
                } label: {
                    FinanceCard {
                        HStack {
                            Text("Monthly budget").font(.headline)
                            Spacer()
                            if let overallBudget {
                                let spent = FinanceMath.spending(for: store.transactions, categoryID: nil, from: period.start, to: period.end)
                                Text("\(Int(FinanceMath.budgetProgress(spentMinor: spent, limitMinor: overallBudget.amountMinor) * 100))%")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(FinTrackStyle.purple)
                            }
                        }
                        if let overallBudget {
                            let spent = FinanceMath.spending(for: store.transactions, categoryID: nil, from: period.start, to: period.end)
                            ProgressView(value: FinanceMath.budgetProgress(spentMinor: spent, limitMinor: overallBudget.amountMinor))
                                .tint(FinTrackStyle.purple)
                                .padding(.vertical, 5)
                            Text("\(Money.formatted(overallBudget.amountMinor - spent)) remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Set a monthly limit to follow your spending.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Text("Recent transactions")
                    .font(.headline)
                    .foregroundStyle(FinTrackStyle.ink)
                let recent = Array(store.transactions.prefix(4))
                if recent.isEmpty {
                    FinanceCard {
                        Text("Your transactions will appear here.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    FinanceCard {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, transaction in
                                TransactionRow(
                                    transaction: transaction,
                                    categoryName: store.categories.first(where: { $0.id == transaction.categoryID })?.name ?? transaction.kind.title
                                )
                                .padding(.vertical, 8)
                                if index < recent.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("FinTrack")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingEditor = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showingEditor) { TransactionEditorView() }
    }

    private func summaryItem(_ title: String, amount: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.formatted(amount))
                .font(.headline)
                .foregroundStyle(color)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }
}
