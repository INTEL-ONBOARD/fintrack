import AppIntents
import UIKit

private enum ShortcutInputError: LocalizedError {
    case invalidMessage
    case invalidAmount
    case cannotOpenApp

    var errorDescription: String? {
        switch self {
        case .invalidMessage: "Enter a financial message of at most 2,048 characters."
        case .invalidAmount: "Enter a positive LKR amount with no more than two decimal places."
        case .cannotOpenApp: "FinTrack could not open the review screen."
        }
    }
}

private enum ShortcutNavigation {
    @MainActor
    static func open(_ draft: PendingShortcutDraft, route: ShortcutDraftRoute) async throws {
        guard let handoff = ShortcutDraftInbox.shared.enqueue(draft, route: route) else {
            throw ShortcutInputError.cannotOpenApp
        }
        let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UIApplication.shared.open(handoff.url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
        if !opened {
            ShortcutDraftInbox.shared.discard(id: handoff.id)
            throw ShortcutInputError.cannotOpenApp
        }
    }
}

struct ImportFinancialMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Financial Message"
    static let description = IntentDescription("Review a bank message as a FinTrack transaction.")
    static let openAppWhenRun = true

    @Parameter(title: "Message Text") var message: String
    @Parameter(title: "Sender") var sender: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_048 else { throw ShortcutInputError.invalidMessage }

        let parsed = FinancialMessageParser.parse(text, sender: sender)
        let bankDraft: FinancialMessageDraft
        let warning: String?
        switch parsed {
        case .ignored:
            return .result(dialog: "This message does not describe a completed transaction.")
        case .ready(let draft):
            bankDraft = draft
            warning = nil
        case .reviewRequired(let draft, let reason):
            bankDraft = draft
            warning = switch reason {
            case .conflictingDirection: "Check whether this is money in or out."
            case .transferDirection: "Check the transfer direction before saving."
            case .multipleAmounts: "Check the transaction amount before saving."
            case .missingCounterparty: "Add the merchant or person before saving."
            case .currencyNeedsConfirmation: "Confirm the currency before saving."
            }
        }

        let kind: TransactionKind = switch bankDraft.kind {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        case .refund: .refund
        case .cashWithdrawal: .cashWithdrawal
        case .bankFee: .bankFee
        case .interest: .interest
        }
        let transaction = FinanceTransaction(
            kind: kind,
            amountMinor: bankDraft.amountMinorUnits,
            merchant: bankDraft.counterparty ?? "",
            source: .sms,
            externalReference: "sms:" + bankDraft.fingerprint
        )
        try await ShortcutNavigation.open(
            PendingShortcutDraft(transaction: transaction, reviewWarning: warning),
            route: .messageImport
        )
        return .result(dialog: "Review the transaction in FinTrack before saving.")
    }
}

private enum QuickAddShortcut {
    @MainActor
    static func open(kind: TransactionKind, amount: String, merchant: String?) async throws {
        guard let amountMinor = Money.minorUnits(from: amount) else { throw ShortcutInputError.invalidAmount }
        let transaction = FinanceTransaction(
            kind: kind,
            amountMinor: amountMinor,
            merchant: (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            source: .siri
        )
        try await ShortcutNavigation.open(
            PendingShortcutDraft(transaction: transaction, reviewWarning: nil),
            route: .quickAdd
        )
    }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Review a new expense in FinTrack.")
    static let openAppWhenRun = true

    @Parameter(title: "Amount in LKR") var amount: String
    @Parameter(title: "Merchant") var merchant: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await QuickAddShortcut.open(kind: .expense, amount: amount, merchant: merchant)
        return .result(dialog: "Review and save your expense in FinTrack.")
    }
}

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Income"
    static let description = IntentDescription("Review new income in FinTrack.")
    static let openAppWhenRun = true

    @Parameter(title: "Amount in LKR") var amount: String
    @Parameter(title: "Source") var source: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await QuickAddShortcut.open(kind: .income, amount: amount, merchant: source)
        return .result(dialog: "Review and save your income in FinTrack.")
    }
}

struct FinTrackAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: ["Add an expense in \(.applicationName)"],
            shortTitle: "Add Expense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: ["Add income in \(.applicationName)"],
            shortTitle: "Add Income",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: MonthlySpendingIntent(),
            phrases: ["How much did I spend this month in \(.applicationName)"],
            shortTitle: "Monthly Spending",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: BudgetStatusIntent(),
            phrases: ["What is my budget status in \(.applicationName)"],
            shortTitle: "Budget Status",
            systemImageName: "chart.pie"
        )
    }
}
