import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var showingEditor = false
    @State private var entryKind: TransactionKind = .expense
    @State private var selectedTransaction: FinanceTransaction?

    private var period: DateInterval { FinanceMath.monthInterval(containing: .now) }
    private var totals: ReportTotals {
        FinanceMath.totals(for: store.transactions, from: period.start, to: period.end)
    }
    private var overallBudget: FinanceBudget? {
        store.budgets.first { $0.month == FinanceMath.monthKey(for: .now) && $0.categoryID == nil }
    }
    private var insights: [OnDeviceInsight] {
        OnDeviceInsights.make(
            for: .now,
            transactions: store.transactions,
            categories: store.categories,
            budgets: store.budgets
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                            Text("FinTrack")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        NavigationLink {
                            TransactionsView()
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("Search transactions")
                    }
                    .padding(.top, 24)

                    Text("THIS MONTH’S NET CASH FLOW")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 8)
                    Text(Money.formatted(totals.netMinor))
                        .font(.system(size: 43, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    HStack(spacing: 10) {
                        Button {
                            entryKind = .expense
                            showingEditor = true
                        } label: { Label("Add expense", systemImage: "plus") }
                            .buttonStyle(DarkPillButtonStyle())
                        Button {
                            entryKind = .income
                            showingEditor = true
                        } label: { Label("Add income", systemImage: "arrow.down.left") }
                            .buttonStyle(DarkPillButtonStyle())
                    }
                    .padding(.bottom, 54)
                }
                .padding(.horizontal, FinTrackStyle.pageInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FinTrackStyle.black, in: RoundedRectangle(cornerRadius: 30))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 24) {
                    Capsule()
                        .fill(FinTrackStyle.border)
                        .frame(width: 34, height: 5)
                        .frame(maxWidth: .infinity)
                    HStack {
                        Text("Transactions")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        NavigationLink("See all") { TransactionsView() }
                            .font(.subheadline)
                    }

                    let recent = Array(store.transactions.prefix(5))
                    if recent.isEmpty {
                        Text("Your transactions will appear here.")
                            .foregroundStyle(FinTrackStyle.muted)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        VStack(spacing: 18) {
                            ForEach(recent) { transaction in
                                Button {
                                    selectedTransaction = transaction
                                } label: {
                                    TransactionRow(
                                        transaction: transaction,
                                        categoryName: store.categories.first(where: { $0.id == transaction.categoryID })?.name ?? transaction.kind.title
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()
                    HStack {
                        summaryItem("Income", amount: totals.incomeMinor, color: FinTrackStyle.green)
                        Spacer()
                        summaryItem("Expenses", amount: totals.expenseMinor, color: FinTrackStyle.ink)
                    }

                    NavigationLink {
                        BudgetsView()
                    } label: {
                        FinanceCard {
                            HStack {
                                Text("Monthly budget").font(.headline)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            if let overallBudget {
                                let spent = FinanceMath.spending(for: store.transactions, categoryID: nil, from: period.start, to: period.end)
                                ProgressView(value: FinanceMath.budgetProgress(spentMinor: spent, limitMinor: overallBudget.amountMinor))
                                    .tint(FinTrackStyle.black)
                                Text("\(Money.formatted(overallBudget.amountMinor - spent)) remaining")
                                    .font(.caption)
                                    .foregroundStyle(FinTrackStyle.muted)
                            } else {
                                Text("Set a monthly limit to follow your spending.")
                                    .font(.subheadline)
                                    .foregroundStyle(FinTrackStyle.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if !insights.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Insights").font(.title3.weight(.semibold))
                            ForEach(insights) { insight in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: iconName(for: insight.level))
                                        .foregroundStyle(color(for: insight.level))
                                        .frame(width: 32, height: 32)
                                        .background(FinTrackStyle.soft, in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(insight.title).font(.subheadline.weight(.semibold))
                                        Text(insight.message)
                                            .font(.caption)
                                            .foregroundStyle(FinTrackStyle.muted)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(FinTrackStyle.pageInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
                .padding(.top, -29)
            }
        }
        .scrollIndicators(.hidden)
        .background(FinTrackStyle.soft)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEditor) { TransactionEditorView(initialKind: entryKind) }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailView(
                transaction: transaction,
                categoryName: store.categories.first(where: { $0.id == transaction.categoryID })?.name ?? transaction.kind.title
            )
        }
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

    private func iconName(for level: OnDeviceInsightLevel) -> String {
        switch level {
        case .positive: "arrow.down.right.circle"
        case .warning: "exclamationmark.triangle"
        case .information: "lightbulb"
        }
    }

    private func color(for level: OnDeviceInsightLevel) -> Color {
        switch level {
        case .positive: FinTrackStyle.green
        case .warning: .orange
        case .information: FinTrackStyle.black
        }
    }
}
