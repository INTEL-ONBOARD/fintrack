import Foundation
import Testing
@testable import FinTrack

@MainActor
struct ShortcutDraftInboxTests {
    @Test func opaqueLinkCarriesOnlyAnIDAndCanBeConsumedOnce() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inbox = ShortcutDraftInbox(fileURL: fileURL)
        let transaction = FinanceTransaction(
            kind: .expense,
            amountMinor: 485_000,
            merchant: "Keells",
            source: .sms,
            externalReference: "sms:abc123"
        )
        let draft = PendingShortcutDraft(transaction: transaction, reviewWarning: "Check amount")
        guard let handoff = inbox.enqueue(draft, route: .messageImport) else {
            Issue.record("Expected a deep link")
            return
        }

        #expect(handoff.url.scheme == "fintrack")
        #expect(handoff.url.host == "import")
        #expect(handoff.url.absoluteString.contains("Keells") == false)
        #expect(handoff.url.absoluteString.contains("485000") == false)
        #expect(URLComponents(url: handoff.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == handoff.id.uuidString)
        #expect(ShortcutDraftInbox(fileURL: fileURL).take(id: handoff.id)?.transaction == transaction)
        #expect(inbox.take(id: handoff.id) == nil)
    }

    @Test func newerDraftReplacesAnUnclaimedDraft() {
        let inbox = ShortcutDraftInbox(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = PendingShortcutDraft(transaction: FinanceTransaction(kind: .expense, amountMinor: 100), reviewWarning: nil)
        let second = PendingShortcutDraft(transaction: FinanceTransaction(kind: .income, amountMinor: 200), reviewWarning: nil)
        guard let old = inbox.enqueue(first, route: .quickAdd),
              let current = inbox.enqueue(second, route: .quickAdd) else {
            Issue.record("Expected both deep links")
            return
        }

        #expect(inbox.take(id: old.id) == nil)
        #expect(inbox.take(id: current.id)?.transaction.kind == .income)
    }

    @Test func expiredDraftCannotBeOpened() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var currentTime = Date(timeIntervalSince1970: 1_000)
        let inbox = ShortcutDraftInbox(fileURL: fileURL, now: { currentTime })
        let draft = PendingShortcutDraft(transaction: FinanceTransaction(kind: .expense, amountMinor: 100), reviewWarning: nil)
        guard let handoff = inbox.enqueue(draft, route: .quickAdd) else {
            Issue.record("Expected a deep link")
            return
        }
        currentTime.addTimeInterval(601)
        #expect(inbox.take(id: handoff.id) == nil)
    }
}
