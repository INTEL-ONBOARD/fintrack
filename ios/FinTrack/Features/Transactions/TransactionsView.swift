import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var showingEditor = false
    @State private var editing: FinanceTransaction?
    @State private var deleting: FinanceTransaction?

    private let filters = ["All", "Expenses", "Income", "Transfers"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(filters, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                if filtered.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No transactions yet" : "No matching transactions",
                        systemImage: "tray",
                        description: Text(searchText.isEmpty ? "Add an expense or income to get started." : "Try another search or filter.")
                    )
                } else {
                    FinanceCard {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, transaction in
                                Button { editing = transaction } label: {
                                    TransactionRow(
                                        transaction: transaction,
                                        categoryName: store.categories.first(where: { $0.id == transaction.categoryID })?.name ?? transaction.kind.title
                                    )
                                    .padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = transaction }
                                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = transaction }
                                }
                                if index < filtered.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Transactions")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingEditor = true } label: { Image(systemName: "plus") } } }
        .searchable(text: $searchText, prompt: "Search merchant, note or category")
        .sheet(isPresented: $showingEditor) { TransactionEditorView() }
        .sheet(item: $editing) { TransactionEditorView(transaction: $0) }
        .confirmationDialog("Delete this transaction?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("Delete Transaction", role: .destructive) {
                guard let deleting else { return }
                do {
                    try store.delete(deleting)
                } catch { store.errorMessage = error.localizedDescription }
                self.deleting = nil
            }
        }
    }

    private var filtered: [FinanceTransaction] {
        store.transactions.filter { transaction in
            let matchesType: Bool
            switch selectedFilter {
            case "Expenses": matchesType = transaction.kind.isOutflow
            case "Income": matchesType = transaction.kind.isInflow || transaction.kind == .refund
            case "Transfers": matchesType = transaction.kind == .transfer || transaction.kind == .cashWithdrawal
            default: matchesType = true
            }
            guard matchesType else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let category = store.categories.first(where: { $0.id == transaction.categoryID })?.name ?? ""
            return [transaction.merchant, transaction.note, category]
                .contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }
}
