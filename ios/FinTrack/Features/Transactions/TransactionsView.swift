import MapKit
import SwiftUI
import UIKit

struct TransactionsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var showingEditor = false
    @State private var editing: FinanceTransaction?
    @State private var selectedTransaction: FinanceTransaction?
    @State private var deleting: FinanceTransaction?

    private let filters = ["All", "Expenses", "Income", "Transfers"]

    var body: some View {
        ScrollView {
            BrandPageIntro(title: "Activity", subtitle: "Every money movement in one place.", icon: "list.bullet")
                .padding(.horizontal, 16)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 20) {
                if store.isSyncingTransactions {
                    ProgressView("Syncing online transactions…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if auth.isAuthenticated && store.pendingTransactionCount > 0 {
                    Button("Retry online sync (\(store.pendingTransactionCount))") {
                        guard let accessToken = auth.token() else { return }
                        Task { await store.retryPendingTransactions(accessToken: accessToken) }
                    }
                    .font(.subheadline)
                }

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
                                Button { selectedTransaction = transaction } label: {
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
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingEditor = true } label: { Image(systemName: "plus") } } }
        .searchable(text: $searchText, prompt: "Search merchant, note or category")
        .sheet(isPresented: $showingEditor) { TransactionEditorView() }
        .sheet(item: $editing) { TransactionEditorView(transaction: $0) }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailView(
                transaction: transaction,
                categoryName: store.categories.first(where: { $0.id == transaction.categoryID })?.name ?? transaction.kind.title
            )
        }
        .confirmationDialog("Delete this transaction?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("Delete Transaction", role: .destructive) {
                guard let transaction = deleting else { return }
                Task {
                    await store.deleteTransaction(transaction, accessToken: auth.token())
                }
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

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore
    @State private var showingEditor = false

    let transaction: FinanceTransaction
    let categoryName: String

    private var isPositive: Bool {
        transaction.kind.isInflow || transaction.kind == .refund
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    Image(systemName: isPositive ? "arrow.down.left" : "arrow.up.right")
                        .font(.title3.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(FinTrackStyle.soft, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(transaction.merchant.isEmpty ? transaction.kind.title : transaction.merchant)
                            .font(.title3.weight(.semibold))
                        Text(categoryName)
                            .font(.subheadline)
                            .foregroundStyle(FinTrackStyle.muted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(FinTrackStyle.soft, in: Circle())
                    }
                    .accessibilityLabel("Close transaction details")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("\(isPositive ? "+" : "−")\(Money.formatted(transaction.amountMinor))")
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(isPositive ? FinTrackStyle.green : FinTrackStyle.ink)
                    Text(transaction.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(FinTrackStyle.muted)
                }

                Button { showingEditor = true } label: {
                    Label("Edit transaction", systemImage: "pencil")
                }
                .buttonStyle(OutlineButtonStyle())

                VStack(alignment: .leading, spacing: 18) {
                    Text("Details")
                        .font(.title3.weight(.semibold))
                    detailRow("Type", value: transaction.kind.title)
                    detailRow("Category", value: categoryName)
                    if !transaction.paymentMethod.isEmpty {
                        detailRow("Payment method", value: transaction.paymentMethod)
                    }
                    if !transaction.note.isEmpty {
                        detailRow("Note", value: transaction.note)
                    }
                    if !transaction.tags.isEmpty {
                        detailRow("Tags", value: transaction.tags.joined(separator: ", "))
                    }
                }

                if let data = store.receiptImageData(for: transaction.id),
                   let image = UIImage(data: data) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Receipt")
                            .font(.title3.weight(.semibold))
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .accessibilityLabel("Attached receipt")
                        Text("Stored on this device")
                            .font(.caption)
                            .foregroundStyle(FinTrackStyle.muted)
                    }
                }

                if let latitude = transaction.latitude, let longitude = transaction.longitude {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Location")
                            .font(.title3.weight(.semibold))
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Marker(transaction.merchant.isEmpty ? "Transaction" : transaction.merchant,
                                   coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                                .tint(FinTrackStyle.black)
                        }
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                        .environment(\.colorScheme, .dark)
                        .frame(height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        if let locationName = transaction.locationName {
                            Text(locationName)
                                .font(.caption)
                                .foregroundStyle(FinTrackStyle.muted)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(.white)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingEditor) { TransactionEditorView(transaction: transaction) }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(FinTrackStyle.muted)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
