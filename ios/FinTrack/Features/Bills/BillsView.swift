import SwiftUI

struct BillsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @State private var showingEditor = false
    @State private var editing: FinanceBill?
    @State private var deleting: FinanceBill?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.bills.isEmpty { ContentUnavailableView("No bills", systemImage: "calendar.badge.clock", description: Text("Add bills and mark them paid each month.")) }
                ForEach(store.bills) { bill in
                    Button { editing = bill } label: {
                        FinanceCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) { Text(bill.name).font(.headline); Text("Due day \(bill.dueDay) · \(bill.category)").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) { Text(Money.formatted(bill.amountMinor)).font(.headline); Text(bill.paid ? "Paid" : "Unpaid").font(.caption).foregroundStyle(bill.paid ? .green : .orange) }
                            }
                        }
                    }.buttonStyle(.plain)
                    .contextMenu {
                        Button(bill.paid ? "Mark unpaid" : "Mark paid", systemImage: "checkmark.circle") { Task { await store.toggleBill(bill, accessToken: auth.token()) } }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = bill }
                    }
                }
                Button("Add Bill", systemImage: "plus") { showingEditor = true }.buttonStyle(PrimaryButtonStyle())
            }.padding(16)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Bills")
        .sheet(isPresented: $showingEditor) { BillEditorView() }
        .sheet(item: $editing) { BillEditorView(bill: $0) }
        .confirmationDialog("Delete this bill?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Bill", role: .destructive) { guard let deleting else { return }; Task { await store.deleteBill(deleting, accessToken: auth.token()) }; self.deleting = nil }
        }
    }
}

private struct BillEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    let bill: FinanceBill?
    @State private var name: String
    @State private var amount: String
    @State private var dueDay: Int
    @State private var category: String
    @State private var paid: Bool
    @State private var errorMessage: String?

    init(bill: FinanceBill? = nil) {
        self.bill = bill
        _name = State(initialValue: bill?.name ?? "")
        _amount = State(initialValue: bill.map { NSDecimalNumber(value: $0.amountMinor).dividing(by: 100).stringValue } ?? "")
        _dueDay = State(initialValue: bill?.dueDay ?? 1)
        _category = State(initialValue: bill?.category ?? "Bills")
        _paid = State(initialValue: bill?.paid ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Bill name", text: $name)
                TextField("Amount in LKR", text: $amount).keyboardType(.decimalPad)
                Stepper("Due day: \(dueDay)", value: $dueDay, in: 1...31)
                TextField("Category", text: $category)
                Toggle("Paid", isOn: $paid)
                Button("Save Bill") { save() }.buttonStyle(PrimaryButtonStyle()).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            .navigationTitle(bill == nil ? "Add Bill" : "Edit Bill").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .alert("Unable to save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let amountMinor = Money.minorUnits(from: amount) else { errorMessage = "Enter a valid bill amount."; return }
        var value = bill ?? FinanceBill(name: name, amountMinor: amountMinor)
        value.name = name; value.amountMinor = amountMinor; value.dueDay = dueDay; value.category = category; value.paid = paid
        do { try store.save(value); if let token = auth.token() { Task { await store.pushBill(value, accessToken: token) } }; dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}
