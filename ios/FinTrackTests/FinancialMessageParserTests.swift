import Foundation
import Testing
@testable import FinTrack

struct FinancialMessageParserTests {
    @Test func debitWithBalanceUsesPurchaseAmount() {
        let result = FinancialMessageParser.parse(
            "Your card was charged LKR 4,850.00 at Keells on 21/10/2026. Available balance LKR 42,600.00. Ref: ABC12345",
            sender: "BANK"
        )

        guard case .ready(let draft) = result else {
            Issue.record("Expected a ready expense, got \(result)")
            return
        }
        #expect(draft.amountMinorUnits == 485_000)
        #expect(draft.kind == .expense)
        #expect(draft.counterparty == "Keells")
        #expect(draft.reference == "ABC12345")
    }

    @Test func incomePreservesDecimalMinorUnits() {
        let result = FinancialMessageParser.parse("Rs. 85,000.50 credited to your account from ACME Ltd on 21/10/2026")
        guard case .ready(let draft) = result else {
            Issue.record("Expected a ready income, got \(result)")
            return
        }
        #expect(draft.kind == .income)
        #expect(draft.amountMinorUnits == 8_500_050)
        #expect(draft.counterparty == "ACME Ltd")
    }

    @Test func transferRequiresDirectionReview() {
        let result = FinancialMessageParser.parse("LKR 10,000 transferred to Savings on 21/10/2026")
        guard case .reviewRequired(let draft, .transferDirection) = result else {
            Issue.record("Expected transfer review, got \(result)")
            return
        }
        #expect(draft.kind == .transfer)
        #expect(draft.amountMinorUnits == 1_000_000)
    }

    @Test func refundAndBankFeeHaveSpecificKinds() {
        let refund = FinancialMessageParser.parse("Rs 1,250 refunded at Keells on 21/10/2026")
        let fee = FinancialMessageParser.parse("Service charge of LKR 25.50 debited at ABC Bank on 21/10/2026")
        guard case .ready(let refundDraft) = refund,
              case .ready(let feeDraft) = fee else {
            Issue.record("Expected recognized refund and bank fee")
            return
        }
        #expect(refundDraft.kind == .refund)
        #expect(feeDraft.kind == .bankFee)
        #expect(feeDraft.amountMinorUnits == 2_550)
    }

    @Test func rejectsNonTransactions() {
        #expect(FinancialMessageParser.parse("OTP 384920 for payment of LKR 500. Do not share.") == .ignored(.authenticationMessage))
        #expect(FinancialMessageParser.parse("Special offer: save 20% on your next LKR 5,000 purchase") == .ignored(.promotionalMessage))
        #expect(FinancialMessageParser.parse("LKR 2,000 card payment declined at Keells") == .ignored(.unsuccessfulTransaction))
        #expect(FinancialMessageParser.parse("Available balance LKR 50,000") == .ignored(.noTransactionEvent))
    }

    @Test func rejectsMalformedAndOverflowingAmounts() {
        #expect(FinancialMessageParser.parse("LKR 1,25,000 debited at Keells") == .ignored(.invalidAmount))
        #expect(FinancialMessageParser.parse("LKR 12.345 debited at Keells") == .ignored(.invalidAmount))
        #expect(FinancialMessageParser.parse("LKR 92233720368547759 debited at Keells") == .ignored(.invalidAmount))
        #expect(FinancialMessageParser.parse("LKR 12.345 debited at Keells. Available balance LKR 100,000") == .ignored(.invalidAmount))
        #expect(FinancialMessageParser.parse("USD 100 debited at Keells. Available balance LKR 100,000") == .ignored(.noAmount))
    }

    @Test func ambiguousAmountsAndConflictingEventsRequireReview() {
        let ambiguous = FinancialMessageParser.parse("LKR 2,000 paid at Keells; LKR 1,500 paid at Cargills")
        guard case .reviewRequired(_, .multipleAmounts) = ambiguous else {
            Issue.record("Expected amount review, got \(ambiguous)")
            return
        }

        let conflicting = FinancialMessageParser.parse("LKR 2,000 debited and credited at Keells")
        guard case .reviewRequired(_, .conflictingDirection) = conflicting else {
            Issue.record("Expected direction review, got \(conflicting)")
            return
        }
    }

    @Test func fingerprintIsStableAcrossPresentationChanges() {
        let a = FinancialMessageParser.parse("LKR 100 paid at Keells", sender: "Bank")
        let b = FinancialMessageParser.parse(" lkr 100  PAID at Keells ", sender: "bank")
        let c = FinancialMessageParser.parse("LKR 100 paid at Keells", sender: "OTHER")
        guard case .ready(let first) = a,
              case .ready(let second) = b,
              case .ready(let otherSender) = c else {
            Issue.record("Expected ready transactions")
            return
        }
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.fingerprint != otherSender.fingerprint)
    }

    @Test func voiceTextNormalizesRupeesAndPrepositions() {
        let result = FinancialMessageParser.parseVoice("Spent on lunch with Nimal 1850 rupees")

        guard case .ready(let draft) = result else {
            Issue.record("Expected a ready voice expense, got \(result)")
            return
        }
        #expect(draft.kind == .expense)
        #expect(draft.amountMinorUnits == 185_000)
        #expect(draft.counterparty == "lunch with Nimal")
    }

    @Test func voiceRupeeSymbolNeedsCurrencyReview() {
        let result = FinancialMessageParser.parseVoice("I spent ₹1850 on lunch with minimal")
        guard case .reviewRequired(let draft, .currencyNeedsConfirmation) = result else {
            Issue.record("Expected currency review, got \(result)")
            return
        }
        #expect(draft.kind == .expense)
        #expect(draft.amountMinorUnits == 185_000)
        #expect(draft.counterparty == nil)
    }

    @Test func sampathPosAlertFindsMerchantAndAmount() {
        let result = FinancialMessageParser.parse(
            "LKR 4,000.00 debited from AC **6494 via POS at BLUE WAY FILLING STATION 20500692 23/10/2026 20:03:22 To Inq Call 0112303050",
            sender: "SAMPATHTXN"
        )
        guard case .ready(let draft) = result else {
            Issue.record("Expected a ready debit, got \(result)")
            return
        }
        #expect(draft.kind == .expense)
        #expect(draft.amountMinorUnits == 400_000)
        #expect(draft.counterparty == "BLUE WAY FILLING STATION")
    }

    @Test @MainActor func notificationImportSavesClearMessagesOnlyOnce() throws {
        let store = FinanceStore(persistence: PersistenceController(inMemory: true))
        let inbox = PendingMessageReviewInbox(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let debit = "LKR 4,000.00 debited from AC **6494 via POS at BLUE WAY FILLING STATION 20500692 23/10/2026 20:03:22"
        guard case .saved(let expense) = try FinancialMessageImportHandler.process(
            message: debit, sender: "SAMPATHTXN", store: store, reviewInbox: inbox
        ) else {
            Issue.record("Expected the debit to save automatically")
            return
        }
        #expect(expense.kind == .expense)
        #expect(expense.amountMinor == 400_000)
        #expect(store.transactions.count == 1)
        guard case .duplicate = try FinancialMessageImportHandler.process(
            message: debit, sender: "SAMPATHTXN", store: store, reviewInbox: inbox
        ) else {
            Issue.record("Expected a duplicate result")
            return
        }
        #expect(store.transactions.count == 1)

        guard case .saved(let income) = try FinancialMessageImportHandler.process(
            message: "LKR 5,000 credited to your account from ACME Ltd on 23/10/2026",
            sender: "BANK", store: store, reviewInbox: inbox
        ) else {
            Issue.record("Expected the credit to save automatically")
            return
        }
        #expect(income.kind == .income)
        #expect(store.transactions.count == 2)
    }

    @Test @MainActor func ambiguousNotificationWaitsForReview() throws {
        let store = FinanceStore(persistence: PersistenceController(inMemory: true))
        let inboxFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inbox = PendingMessageReviewInbox(fileURL: inboxFileURL)
        let message = "LKR 2,000 debited and credited at Keells"
        guard case .queued = try FinancialMessageImportHandler.process(
            message: message, sender: "BANK", store: store, reviewInbox: inbox
        ) else {
            Issue.record("Expected review instead of automatic saving")
            return
        }
        #expect(store.transactions.isEmpty)
        #expect(inbox.all().count == 1)
        guard case .queued = try FinancialMessageImportHandler.process(
            message: "I paid LKR 500 at Keells", sender: "FRIEND", store: store, reviewInbox: inbox
        ) else {
            Issue.record("Expected a personal message to need review")
            return
        }
        #expect(inbox.all().count == 2)
        #expect(PendingMessageReviewInbox(fileURL: inboxFileURL).all().count == 2)
        guard case .ignored = try FinancialMessageImportHandler.process(
            message: "Your OTP is 123456", sender: "BANK", store: store, reviewInbox: inbox
        ) else {
            Issue.record("Expected OTP to be ignored")
            return
        }
    }
}
