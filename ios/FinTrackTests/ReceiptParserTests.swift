import Testing
@testable import FinTrack

struct ReceiptParserTests {
    @Test func extractsMerchantDateAndGrandTotal() {
        let receipt = """
        TAX INVOICE
        KEELLS SUPER
        Date: 21/10/2026 18:42
        Subtotal Rs 1,200.00
        VAT Rs 50.00
        GRAND TOTAL LKR 1,250.00
        CASH LKR 1,300.00
        CHANGE LKR 50.00
        """

        let draft = ReceiptParser.parse(receipt)
        #expect(draft.merchant == "KEELLS SUPER")
        #expect(draft.date == ReceiptCalendarDate(year: 2026, month: 10, day: 21))
        #expect(draft.totalMinorUnits == 125_000)
        #expect(draft.currencyCode == "LKR")
        #expect(draft.issues.isEmpty)
    }

    @Test func supportsISODateAndDecimalTotal() {
        let draft = ReceiptParser.parse("CARGILLS\nIssued: 2026-10-11\nAmount Due: Rs. 980.50")
        #expect(draft.merchant == "CARGILLS")
        #expect(draft.date == ReceiptCalendarDate(year: 2026, month: 10, day: 11))
        #expect(draft.totalMinorUnits == 98_050)
        #expect(draft.issues.isEmpty)
    }

    @Test func incompleteTextLeavesFieldsForReview() {
        let draft = ReceiptParser.parse("RECEIPT\nThank you\n21/10/2026")
        #expect(draft.merchant == nil)
        #expect(draft.date == ReceiptCalendarDate(year: 2026, month: 10, day: 21))
        #expect(draft.totalMinorUnits == nil)
        #expect(draft.issues == [.missingMerchant, .missingTotal])
    }

    @Test func invalidCalendarDateIsNotAccepted() {
        let draft = ReceiptParser.parse("KEELLS\nDate: 31/02/2026\nTotal LKR 100.00")
        #expect(draft.date == nil)
        #expect(draft.issues == [.missingDate])
    }

    @Test func conflictingTotalsNeedReview() {
        let draft = ReceiptParser.parse("KEELLS\nDate: 21/10/2026\nTOTAL 1,250.00\nTOTAL 1,300.00")
        #expect(draft.totalMinorUnits == 130_000)
        #expect(draft.issues == [.ambiguousTotal])
    }

    @Test func foreignCurrencyCannotBecomeLKRExpense() {
        let draft = ReceiptParser.parse("STORE\nDate: 21/10/2026\nTOTAL USD 20.00")
        #expect(draft.totalMinorUnits == nil)
        #expect(draft.issues == [.unsupportedCurrency])
    }
}
