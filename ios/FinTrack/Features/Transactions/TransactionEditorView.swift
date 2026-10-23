import CoreLocation
import SwiftUI
import UIKit

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession

    private let original: FinanceTransaction?
    private let isReviewDraft: Bool
    private let reviewWarning: String?
    private let receiptImageData: Data?
    @State private var kind: TransactionKind
    @State private var amountText: String
    @State private var categoryID: UUID?
    @State private var merchant: String
    @State private var note: String
    @State private var tagsText: String
    @State private var paymentMethod: String
    @State private var occurredAt: Date
    @State private var transactionCoordinate: CLLocationCoordinate2D?
    @State private var transactionLocationName: String?
    @State private var showingLocationPicker = false
    @State private var errorMessage: String?
    @State private var categorySuggestion: OnDeviceClassificationResult?
    @State private var suggestionText = ""
    @StateObject private var voice = VoiceTransactionService()
    @State private var voiceWarning: String?

    init(
        transaction: FinanceTransaction? = nil, isReviewDraft: Bool = false,
        reviewWarning: String? = nil, initialKind: TransactionKind = .expense,
        receiptImageData: Data? = nil
    ) {
        original = transaction
        self.isReviewDraft = isReviewDraft
        self.reviewWarning = reviewWarning
        self.receiptImageData = receiptImageData
        _kind = State(initialValue: transaction?.kind ?? initialKind)
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
        if let transaction, let latitude = transaction.latitude, let longitude = transaction.longitude {
            _transactionCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        } else {
            _transactionCoordinate = State(initialValue: nil)
        }
        _transactionLocationName = State(initialValue: transaction?.locationName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandPageIntro(title: "Transaction", subtitle: "Record the details that matter.", icon: "arrow.left.arrow.right", showsTitle: false)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                if let warning = reviewWarning ?? voiceWarning {
                    Section {
                        Text(warning)
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

                Section("Voice transaction entry") {
                    Button {
                        Task { await voice.toggleRecording() }
                    } label: {
                        Label(
                            voice.isRecording ? "Stop listening" : "Speak transaction",
                            systemImage: voice.isRecording ? "stop.circle" : "mic"
                        )
                    }
                    if voice.isRecording {
                        Text("Say something like: Spent on lunch with Nimal 1850 rupees.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !voice.transcript.isEmpty {
                        Text(voice.transcript)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Use Voice Details") { applyVoiceTranscript() }
                    }
                    if let errorMessage = voice.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let categorySuggestion, categoryID == nil {
                    Section("On-device suggestion") {
                        HStack {
                            Label(categorySuggestion.categoryName, systemImage: "sparkles")
                            Spacer()
                            Text("\(Int(categorySuggestion.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("This suggestion was made on the device from the merchant and notes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Use \(categorySuggestion.categoryName)") {
                            categoryID = categorySuggestion.categoryID
                        }
                    }
                }

                Section("Details") {
                    TextField("Notes", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Tags, separated by commas", text: $tagsText)
                    TextField("Payment method", text: $paymentMethod)
                }

                if let data = receiptImageData ?? original.flatMap({ store.receiptImageData(for: $0.id) }),
                   let image = UIImage(data: data) {
                    Section("Receipt") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .accessibilityLabel("Attached receipt")
                        Text("Saved on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    Button {
                        showingLocationPicker = true
                    } label: {
                        Label(
                            transactionLocationName ?? (transactionCoordinate == nil ? "Add a place" : "Location selected"),
                            systemImage: transactionCoordinate == nil ? "mappin.and.ellipse" : "checkmark.circle"
                        )
                    }
                    if transactionCoordinate != nil {
                        Button("Remove Location", role: .destructive) {
                            transactionCoordinate = nil
                            transactionLocationName = nil
                        }
                    }
                }

                Section {
                    Button(original == nil || isReviewDraft ? "Save Transaction" : "Save Changes") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .finTrackGroupedScreen()
            .navigationTitle(isReviewDraft ? "Review Transaction" : (original == nil ? "Add Transaction" : "Edit Transaction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView(coordinate: $transactionCoordinate, locationName: $transactionLocationName)
            }
            .onAppear { updateCategorySuggestion() }
            .onChange(of: merchant) { _, _ in updateCategorySuggestion() }
            .onChange(of: note) { _, _ in updateCategorySuggestion() }
            .onChange(of: kind) { _, _ in
                categoryID = nil
                updateCategorySuggestion()
            }
            .onChange(of: categoryID) { _, value in
                if let suggestion = categorySuggestion,
                   let value,
                   let chosenCategory = store.categories.first(where: { $0.id == value }) {
                    OnDeviceClassifierFeedback.record(
                        text: suggestionText,
                        suggestion: suggestion,
                        chosenCategory: chosenCategory
                    )
                }
                if value != nil { categorySuggestion = nil }
                else { updateCategorySuggestion() }
            }
            .alert("Unable to save", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var availableCategories: [FinanceCategory] {
        store.categories.filter { $0.kind == (kind.isInflow ? .income : .expense) }
    }

    private func updateCategorySuggestion() {
        guard categoryID == nil else {
            categorySuggestion = nil
            return
        }
        suggestionText = "\(merchant) \(note)"
        categorySuggestion = OnDeviceTransactionClassifier().suggest(
            text: suggestionText,
            kind: kind,
            categories: availableCategories
        )
    }

    private func applyVoiceTranscript() {
        switch FinancialMessageParser.parseVoice(voice.transcript) {
        case .ignored:
            voice.errorMessage = "The voice text did not contain a usable transaction."
        case let .ready(draft):
            applyVoiceDraft(draft, warning: nil)
        case let .reviewRequired(draft, reason):
            let warning: String = switch reason {
            case .conflictingDirection: "Check whether this is money in or out."
            case .transferDirection: "Check the transfer direction before saving."
            case .multipleAmounts: "Check which amount should be saved."
            case .missingCounterparty: "Add the merchant or person before saving."
            case .currencyNeedsConfirmation: "Confirm this amount is in Sri Lankan rupees and check the merchant before saving."
            }
            applyVoiceDraft(draft, warning: warning)
        }
    }

    private func applyVoiceDraft(_ draft: FinancialMessageDraft, warning: String?) {
        kind = TransactionKind(rawValue: draft.kind.rawValue) ?? .expense
        amountText = NSDecimalNumber(value: draft.amountMinorUnits)
            .dividing(by: NSDecimalNumber(value: 100))
            .stringValue
        merchant = draft.counterparty ?? ""
        categoryID = nil
        voiceWarning = warning
        updateCategorySuggestion()
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
        transaction.latitude = transactionCoordinate?.latitude
        transaction.longitude = transactionCoordinate?.longitude
        transaction.locationName = transactionLocationName
        do {
            try store.save(transaction, receiptImageData: receiptImageData)
            if let accessToken = auth.token() {
                Task { await store.pushTransaction(transaction, accessToken: accessToken) }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
