import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var auth: AuthSession
    @State private var messageText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isScanning = false
    @State private var reviewDraft: FinanceTransaction?
    @State private var statusMessage: String?
    @State private var selectedStatementData: Data?
    @State private var selectedStatementName = ""
    @State private var statementAnalysis: StatementAnalysis?
    @State private var accountName = ""
    @State private var bankLabel = ""
    @State private var isAnalyzingStatement = false
    @State private var isCommittingStatement = false
    @State private var showingStatementPicker = false

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
                    Text("Bank statement").font(.headline)
                    Text("Upload a CSV, Excel or PDF statement and review the detected rows before importing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Choose Statement", systemImage: "doc.badge.plus") { showingStatementPicker = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isAnalyzingStatement || isCommittingStatement)
                    if isAnalyzingStatement { ProgressView("Analyzing statement…") }
                    if let statementAnalysis {
                        statementPreview(statementAnalysis)
                    }
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
        .fileImporter(
            isPresented: $showingStatementPicker,
            allowedContentTypes: [.commaSeparatedText, .spreadsheet, .pdf]
        ) { result in
            switch result {
            case .success(let url): Task { await analyzeStatement(url) }
            case .failure(let error): statusMessage = error.localizedDescription
            }
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

    @ViewBuilder
    private func statementPreview(_ analysis: StatementAnalysis) -> some View {
        Divider().padding(.vertical, 4)
        Text(selectedStatementName).font(.subheadline.bold())
        if let confidence = analysis.confidence {
            Text("Detection confidence: \(Int(confidence * 100))%")
                .font(.caption).foregroundStyle(.secondary)
        }
        TextField("Account name", text: $accountName)
            .textFieldStyle(.roundedBorder)
        TextField("Bank label (optional)", text: $bankLabel)
            .textFieldStyle(.roundedBorder)
        ForEach(Array((analysis.preview ?? []).prefix(5).enumerated()), id: \.offset) { _, row in
            HStack {
                Text(row.date).font(.caption)
                Text(row.name).lineLimit(1)
                Spacer()
                Text(String(format: "%.2f", row.amount)).font(.caption.monospacedDigit())
            }
        }
        if analysis.mapping != nil {
            Button("Import Statement") { Task { await commitStatement(analysis) } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommittingStatement)
        } else {
            Text("The server did not return a usable column mapping.")
                .font(.caption).foregroundStyle(.red)
        }
        if isCommittingStatement { ProgressView("Importing statement…") }
    }

    private func analyzeStatement(_ url: URL) async {
        guard let token = auth.token() else {
            statusMessage = "Sign in before uploading a bank statement."
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = "The selected statement could not be opened."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        isAnalyzingStatement = true
        defer { isAnalyzingStatement = false }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 10 * 1024 * 1024 else {
                statusMessage = "Statements must be 10 MB or smaller."
                return
            }
            selectedStatementData = data
            selectedStatementName = url.lastPathComponent
            statementAnalysis = try await store.analyzeStatement(
                fileData: data, fileName: url.lastPathComponent, accessToken: token
            )
            accountName = store.accounts.first?.name ?? ""
            statusMessage = "Review the detected rows before importing."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func commitStatement(_ analysis: StatementAnalysis) async {
        guard let data = selectedStatementData, let mapping = analysis.mapping,
              let token = auth.token() else { return }
        isCommittingStatement = true
        defer { isCommittingStatement = false }
        do {
            let result = try await store.commitStatement(
                fileData: data, fileName: selectedStatementName,
                accountName: accountName.trimmingCharacters(in: .whitespacesAndNewlines),
                mapping: mapping, fingerprint: analysis.fingerprint,
                bankLabel: bankLabel.isEmpty ? nil : bankLabel, accessToken: token
            )
            statusMessage = "Imported \(result.imported) transactions. Skipped \(result.skipped) duplicates."
            statementAnalysis = nil
            selectedStatementData = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
