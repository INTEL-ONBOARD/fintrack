import SwiftUI

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore

    private let original: FinanceTransaction?
    private let isReviewDraft: Bool
    private let reviewWarning: String?
    @State private var kind: TransactionKind
    @State private var amountText: String
    @State private var categoryID: UUID?
    @State private var merchant: String
    @State private var note: String
    @State private var tagsText: String
    @State private var paymentMethod: String
    @State private var occurredAt: Date
    @State private var errorMessage: String?

    init(transaction: FinanceTransaction? = nil, isReviewDraft: Bool = false, reviewWarning: String? = nil) {
        original = transaction
        self.isReviewDraft = isReviewDraft
        self.reviewWarning = reviewWarning
        _kind = State(initialValue: transaction?.kind ?? .expense)
        let amount = transaction.map {
            NSDecimalNumber(value: $0.amountMinor).dividing(by: NSDecimalNumber(value: 100)).stringValue
        } ?? ""
        _amountText = State(initialValue: amount)
        _categoryID = State(initialValue: transaction?.categoryID)
        _merchant = State(initialValue: transaction?.merchant ?? "")
        _note = State(initialValue: transaction?.note ?? "")
        _tagsText = State(initialValue: transaction?.tags.joined(separator: ", ") ?? "")
        _paymentMethod = State(initialValue: transaction?.paymentMethod ?? "")
        _occurredAt = State(initialValue: transaction?.occurredAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let reviewWarning {
                    Section {
                        Text(reviewWarning)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(TransactionKind.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .onChange(of: kind) { _, _ in categoryID = nil }
                    TextField("Amount in LKR", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Amount in Sri Lankan rupees")
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(availableCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    TextField("Merchant / Person", text: $merchant)
                    DatePicker("Date & time", selection: $occurredAt)
                }

                Section("Details") {
                    TextField("Notes", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Tags, separated by commas", text: $tagsText)
                    TextField("Payment method", text: $paymentMethod)
                }

                Section {
                    Button(original == nil || isReviewDraft ? "Save Transaction" : "Save Changes") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(isReviewDraft ? "Review Transaction" : (original == nil ? "Add Transaction" : "Edit Transaction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .alert("Unable to save", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var availableCategories: [FinanceCategory] {
        store.categories.filter { $0.kind == (kind.isInflow ? .income : .expense) }
    }

    private func save() {
        guard let amountMinor = Money.minorUnits(from: amountText) else {
            errorMessage = "Enter a positive amount with no more than two decimal places."
            return
        }
        var transaction = original ?? FinanceTransaction(kind: kind, amountMinor: amountMinor)
        transaction.kind = kind
        transaction.amountMinor = amountMinor
        transaction.categoryID = categoryID
        transaction.merchant = merchant
        transaction.note = note
        transaction.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        transaction.paymentMethod = paymentMethod
        transaction.occurredAt = occurredAt
        do {
            try store.save(transaction)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
