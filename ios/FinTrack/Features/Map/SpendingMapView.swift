import CoreLocation
import MapKit
import SwiftUI

struct SpendingMapView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selectedFilter = "All"
    @State private var selectedDateFilter: DateFilter = .all
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var customEnd = Date.now
    @State private var draftStart = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var draftEnd = Date.now
    @State private var showingCustomDates = false
    @State private var selectedTransaction: FinanceTransaction?
    @State private var position: MapCameraPosition = .automatic

    private let filters = ["All", "Expenses", "Income"]

    private enum DateFilter: String, CaseIterable {
        case all = "All dates"
        case today = "Today"
        case lastSevenDays = "Last 7 days"
        case thisMonth = "This month"
        case lastMonth = "Last month"
        case custom = "Custom range"
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandPageIntro(title: "Spending map", subtitle: "See the places behind your transactions.", icon: "map")
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Picker("Map filter", selection: $selectedFilter) {
                ForEach(filters, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HStack {
                Text("Date")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FinTrackStyle.muted)
                Spacer()
                Menu {
                    ForEach(DateFilter.allCases, id: \.self) { filter in
                        Button(filter.rawValue, systemImage: selectedDateFilter == filter ? "checkmark" : "calendar") {
                            if filter == .custom {
                                draftStart = customStart
                                draftEnd = customEnd
                                showingCustomDates = true
                            } else {
                                selectedDateFilter = filter
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(dateFilterTitle)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FinTrackStyle.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(FinTrackStyle.soft, in: Capsule())
                }
                .accessibilityLabel("Date filter, \(dateFilterTitle)")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if locatedTransactions.isEmpty {
                ContentUnavailableView(
                    hasLocatedTransactions ? "No places for these filters" : "No transactions with locations",
                    systemImage: "map",
                    description: Text(hasLocatedTransactions
                        ? "Try another date or transaction type."
                        : "Add a location while creating an expense or income.")
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
                                    .background(transaction.kind.isInflow ? FinTrackStyle.green : FinTrackStyle.black, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                            .accessibilityLabel(annotationTitle(for: transaction))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            }
        }
        .background(FinTrackStyle.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedTransaction) {
            TransactionDetailView(transaction: $0, categoryName: categoryName(for: $0))
        }
        .sheet(isPresented: $showingCustomDates) {
            NavigationStack {
                Form {
                    DatePicker("From", selection: $draftStart, in: ...draftEnd, displayedComponents: .date)
                    DatePicker("To", selection: $draftEnd, in: draftStart..., displayedComponents: .date)
                }
                .navigationTitle("Choose dates")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCustomDates = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            customStart = draftStart
                            customEnd = draftEnd
                            selectedDateFilter = .custom
                            position = .automatic
                            showingCustomDates = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: selectedFilter) { _, _ in position = .automatic }
        .onChange(of: selectedDateFilter) { _, _ in position = .automatic }
    }

    private var hasLocatedTransactions: Bool {
        store.transactions.contains { $0.latitude != nil && $0.longitude != nil }
    }

    private var dateFilterTitle: String {
        if selectedDateFilter == .custom {
            return "\(customStart.formatted(date: .abbreviated, time: .omitted)) – \(customEnd.formatted(date: .abbreviated, time: .omitted))"
        }
        return selectedDateFilter.rawValue
    }

    private var dateRange: Range<Date>? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        switch selectedDateFilter {
        case .all:
            return nil
        case .today:
            return today..<(calendar.date(byAdding: .day, value: 1, to: today) ?? .distantFuture)
        case .lastSevenDays:
            return (calendar.date(byAdding: .day, value: -6, to: today) ?? today)..<(calendar.date(byAdding: .day, value: 1, to: today) ?? .distantFuture)
        case .thisMonth:
            guard let month = calendar.dateInterval(of: .month, for: today) else { return nil }
            return month.start..<month.end
        case .lastMonth:
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: today),
                  let month = calendar.dateInterval(of: .month, for: lastMonth) else { return nil }
            return month.start..<month.end
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? .distantFuture
            return start..<end
        }
    }

    private var locatedTransactions: [FinanceTransaction] {
        let selectedRange = dateRange
        return store.transactions.filter { transaction in
            guard transaction.latitude != nil, transaction.longitude != nil else { return false }
            if let selectedRange, !selectedRange.contains(transaction.occurredAt) { return false }
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
