import CoreLocation
import MapKit
import SwiftUI

struct SpendingMapView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selectedFilter = "All"
    @State private var selectedTransaction: FinanceTransaction?
    @State private var position: MapCameraPosition = .automatic

    private let filters = ["All", "Expenses", "Income"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Map filter", selection: $selectedFilter) {
                ForEach(filters, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(16)

            if locatedTransactions.isEmpty {
                ContentUnavailableView(
                    "No transactions with locations",
                    systemImage: "map",
                    description: Text("Add a location while creating an expense or income.")
                )
            } else {
                Map(position: $position) {
                    ForEach(locatedTransactions) { transaction in
                        Annotation(annotationTitle(for: transaction), coordinate: coordinate(for: transaction)) {
                            Button {
                                selectedTransaction = transaction
                            } label: {
                                Image(systemName: transaction.kind.isInflow ? "arrow.down.left" : "arrow.up.right")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(9)
                                    .background(transaction.kind.isInflow ? FinTrackStyle.green : FinTrackStyle.purple, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                            .accessibilityLabel(annotationTitle(for: transaction))
                        }
                    }
                }
                .mapStyle(.standard)
            }
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Spending Map")
        .sheet(item: $selectedTransaction) {
            MapTransactionDetail(transaction: $0, categoryName: categoryName(for: $0))
        }
    }

    private var locatedTransactions: [FinanceTransaction] {
        store.transactions.filter { transaction in
            guard transaction.latitude != nil, transaction.longitude != nil else { return false }
            switch selectedFilter {
            case "Expenses": return transaction.kind.isOutflow
            case "Income": return transaction.kind.isInflow || transaction.kind == .refund
            default: return true
            }
        }
    }

    private func coordinate(for transaction: FinanceTransaction) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: transaction.latitude ?? 0, longitude: transaction.longitude ?? 0)
    }

    private func categoryName(for transaction: FinanceTransaction) -> String {
        store.categories.first(where: { $0.id == transaction.categoryID })?.name ?? transaction.kind.title
    }

    private func annotationTitle(for transaction: FinanceTransaction) -> String {
        "\(transaction.merchant.isEmpty ? transaction.kind.title : transaction.merchant), \(Money.formatted(transaction.amountMinor))"
    }
}

private struct MapTransactionDetail: View {
    @Environment(\.dismiss) private var dismiss
    let transaction: FinanceTransaction
    let categoryName: String

    var body: some View {
        NavigationStack {
            FinanceCard {
                Text(transaction.merchant.isEmpty ? transaction.kind.title : transaction.merchant)
                    .font(.title3.bold())
                Text(categoryName).foregroundStyle(.secondary)
                Text(Money.formatted(transaction.amountMinor))
                    .font(.title2.bold())
                    .foregroundStyle(transaction.kind.isInflow ? FinTrackStyle.green : FinTrackStyle.purple)
                Text(transaction.occurredAt.formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let locationName = transaction.locationName {
                    Label(locationName, systemImage: "mappin.and.ellipse")
                }
            }
            .padding(16)
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
