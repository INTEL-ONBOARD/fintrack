import SwiftUI

struct BudgetsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selectedMonth = Date.now
    @State private var showingEditor = false
    @State private var editing: FinanceBudget?
    @State private var deleting: FinanceBudget?

    private var monthKey: String { FinanceMath.monthKey(for: selectedMonth) }
    private var period: DateInterval { FinanceMath.monthInterval(containing: selectedMonth) }
    private var current: [FinanceBudget] {
        store.budgets.filter { $0.month == monthKey }
            .sorted { ($0.categoryID == nil) && ($1.categoryID != nil) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker("Budget month", selection: $selectedMonth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                if current.isEmpty {
                    ContentUnavailableView(
                        "No budgets for this month", systemImage: "chart.pie",
                        description: Text("Create an overall limit or a category budget.")
                    )
                }
                ForEach(current) { budget in
                    let spent = FinanceMath.spending(
                        for: store.transactions, categoryID: budget.categoryID,
                        from: period.start, to: period.end
                    )
                    Button { editing = budget } label: {
                        FinanceCard {
                            HStack {
                                Text(budget.categoryID.flatMap { id in store.categories.first(where: { $0.id == id })?.name } ?? "Overall budget")
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(FinanceMath.budgetProgress(spentMinor: spent, limitMinor: budget.amountMinor) * 100))%")
                                    .foregroundStyle(FinTrackStyle.purple)
                                    .font(.subheadline.bold())
                            }
                            ProgressView(value: FinanceMath.budgetProgress(spentMinor: spent, limitMinor: budget.amountMinor))
                                .tint(spent > budget.amountMinor ? .red : FinTrackStyle.purple)
                                .padding(.vertical, 6)
                            HStack {
                                Text("\(Money.formatted(spent)) spent")
                                Spacer()
                                Text("\(Money.formatted(budget.amountMinor - spent)) left")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if spent > budget.amountMinor {
                                Text("Budget exceeded")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { deleting = budget } }
                }
                Button("Add Budget", systemImage: "plus") { showingEditor = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Budgets")
        .sheet(isPresented: $showingEditor) { BudgetEditorView(month: selectedMonth) }
        .sheet(item: $editing) { BudgetEditorView(month: selectedMonth, budget: $0) }
        .confirmationDialog("Delete this budget?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("Delete Budget", role: .destructive) {
                guard let deleting else { return }
                do {
                    try store.delete(deleting)
                } catch { store.errorMessage = error.localizedDescription }
                self.deleting = nil
            }
        }
    }
}

private struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore
    let month: Date
    let budget: FinanceBudget?
    @State private var categoryID: UUID?
    @State private var amountText: String
    @State private var errorMessage: String?

    init(month: Date, budget: FinanceBudget? = nil) {
        self.month = month
        self.budget = budget
        _categoryID = State(initialValue: budget?.categoryID)
        let amount = budget.map { NSDecimalNumber(value: $0.amountMinor).dividing(by: NSDecimalNumber(value: 100)).stringValue } ?? ""
        _amountText = State(initialValue: amount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $categoryID) {
                    Text("Overall budget").tag(Optional<UUID>.none)
                    ForEach(store.categories.filter { $0.kind == .expense }) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                TextField("Monthly limit in LKR", text: $amountText)
                    .keyboardType(.decimalPad)
                Button("Save Budget") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .navigationTitle(budget == nil ? "Add Budget" : "Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .alert("Unable to save", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let amountMinor = Money.minorUnits(from: amountText) else {
            errorMessage = "Enter a positive amount with no more than two decimal places."
            return
        }
        let key = FinanceMath.monthKey(for: month)
        let existing = budget ?? store.budgets.first {
            $0.month == key && $0.categoryID == categoryID
        }
        var value = existing ?? FinanceBudget(month: key, categoryID: categoryID, amountMinor: amountMinor)
        value.categoryID = categoryID
        value.amountMinor = amountMinor
        do {
            try store.save(value)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
