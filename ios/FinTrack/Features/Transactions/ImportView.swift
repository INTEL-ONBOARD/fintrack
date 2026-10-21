import PhotosUI
import SwiftUI

struct ImportView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var messageText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isScanning = false
    @State private var reviewDraft: FinanceTransaction?
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Review imported details before saving them to your ledger.")
                    .foregroundStyle(.secondary)

                FinanceCard {
                    Text("Financial message").font(.headline)
                    Text("Paste a bank alert or send one through a Shortcut.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $messageText)
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(FinTrackStyle.border))
                        .accessibilityLabel("Financial message text")
                    Button("Review Message") { parseMessage() }
                        .buttonStyle(PrimaryButtonStyle())
                }

                FinanceCard {
                    Text("Receipt or bill").font(.headline)
                    Text("Pick an image. Text recognition runs on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Image", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isScanning)
                    if isScanning { ProgressView("Reading image…") }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(16)
        }
        .background(FinTrackStyle.background)
        .navigationTitle("Import")
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await scan(item) }
        }
        .sheet(item: $reviewDraft) {
            TransactionEditorView(transaction: $0, isReviewDraft: true, reviewWarning: statusMessage)
        }
    }

    private func parseMessage() {
        switch FinancialMessageParser.parse(messageText) {
        case .ignored(let reason):
            statusMessage = "No transaction could be imported (\(String(describing: reason)))."
        case .ready(let draft), .reviewRequired(let draft, _):
            let reference = "sms:" + draft.fingerprint
            if store.transactions.contains(where: { $0.externalReference == reference && $0.source == .sms }) {
                statusMessage = "This message has already been imported."
                return
            }
            let kind = TransactionKind(rawValue: draft.kind.rawValue) ?? .expense
            reviewDraft = FinanceTransaction(
                kind: kind, amountMinor: draft.amountMinorUnits,
                merchant: draft.counterparty ?? "", source: .sms,
                externalReference: reference
            )
            statusMessage = "Check the amount, type and category before saving."
        }
    }

    private func scan(_ item: PhotosPickerItem) async {
        isScanning = true
        defer { isScanning = false }
        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                statusMessage = "The selected image could not be opened."
                return
            }
            let text = try await ReceiptTextRecognizer().recognizeText(in: imageData)
            let draft = ReceiptParser.parse(text)
            var date = Date.now
            if let parsedDate = draft.date,
               let value = Calendar.current.date(from: DateComponents(
                year: parsedDate.year, month: parsedDate.month, day: parsedDate.day,
                hour: 12
               )) { date = value }
            reviewDraft = FinanceTransaction(
                kind: .expense, amountMinor: draft.totalMinorUnits ?? 0,
                occurredAt: date, merchant: draft.merchant ?? "",
                note: "Scanned receipt", source: .receipt
            )
            statusMessage = draft.issues.isEmpty
                ? "Review the extracted transaction before saving."
                : "Some receipt details need your review."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
