import Foundation

enum FinancialMessageKind: String, Equatable, Sendable {
    case expense
    case income
    case transfer
    case refund
    case cashWithdrawal
    case bankFee
    case interest
}

struct FinancialMessageDraft: Equatable, Sendable {
    let amountMinorUnits: Int64
    let currencyCode: String
    let kind: FinancialMessageKind
    let counterparty: String?
    let reference: String?
    let fingerprint: String
}

enum FinancialMessageParseResult: Equatable, Sendable {
    enum IgnoreReason: Equatable, Sendable {
        case authenticationMessage
        case promotionalMessage
        case unsuccessfulTransaction
        case noTransactionEvent
        case noAmount
        case invalidAmount
    }

    enum ReviewReason: Equatable, Sendable {
        case conflictingDirection
        case transferDirection
        case multipleAmounts
        case missingCounterparty
    }

    case ignored(IgnoreReason)
    case reviewRequired(FinancialMessageDraft, ReviewReason)
    case ready(FinancialMessageDraft)
}

enum FinancialMessageParser {
    static func parse(_ message: String, sender: String? = nil) -> FinancialMessageParseResult {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .ignored(.noTransactionEvent) }

        if contains(#"\b(?:OTP|one[ -]time (?:password|passcode|code)|verification code|security code|passcode|password|2FA)\b"#, in: text) {
            return .ignored(.authenticationMessage)
        }
        if contains(#"\b(?:declined|failed|rejected|cancelled|canceled)\b"#, in: text),
           !contains(#"\b(?:refund(?:ed)?|revers(?:al|ed))\b"#, in: text) {
            return .ignored(.unsuccessfulTransaction)
        }

        let refund = contains(#"\b(?:refund(?:ed)?|revers(?:al|ed))\b"#, in: text)
        let transfer = contains(#"\b(?:transfer(?:red)?|remitt(?:ed|ance))\b"#, in: text)
        let withdrawal = contains(#"\b(?:withdrawn?|withdrawal|withdrew)\b"#, in: text)
        let bankFee = contains(#"\b(?:bank fee|service charge|annual fee|processing fee)\b"#, in: text)
        let interest = contains(#"\binterest (?:paid|credited|earned)\b|\binterest credit\b"#, in: text)
        let income = contains(#"\b(?:credited|credit (?:of|to|with)|received|deposited|deposit of|salary credited)\b"#, in: text)
        let expense = contains(#"\b(?:debited|debit of|charged|spent|paid|purchased|purchase at|payment made)\b"#, in: text)

        if contains(#"\b(?:promotion|promo|special offer|discount|coupon|apply now|reward points)\b"#, in: text),
           !(refund || transfer || withdrawal || bankFee || interest || income || expense) {
            return .ignored(.promotionalMessage)
        }

        let kind: FinancialMessageKind
        if refund { kind = .refund }
        else if transfer { kind = .transfer }
        else if withdrawal { kind = .cashWithdrawal }
        else if bankFee { kind = .bankFee }
        else if interest { kind = .interest }
        else if income && !expense { kind = .income }
        else if expense { kind = .expense }
        else { return .ignored(.noTransactionEvent) }

        let amounts = extractAmounts(from: text)
        if amounts.foundInvalid { return .ignored(.invalidAmount) }
        guard !amounts.valid.isEmpty else {
            return .ignored(.noAmount)
        }

        let ranked = amounts.valid.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.position < rhs.position : lhs.score > rhs.score
        }
        let selected = ranked[0]
        if selected.score < 0 { return .ignored(.noAmount) }
        let draft = FinancialMessageDraft(
            amountMinorUnits: selected.amountMinorUnits,
            currencyCode: "LKR",
            kind: kind,
            counterparty: extractCounterparty(from: text),
            reference: extractReference(from: text),
            fingerprint: fingerprint(for: text, sender: sender)
        )

        if income && expense && !refund && !transfer {
            return .reviewRequired(draft, .conflictingDirection)
        }
        if transfer { return .reviewRequired(draft, .transferDirection) }
        if ranked.count > 1 && ranked[0].score <= ranked[1].score {
            return .reviewRequired(draft, .multipleAmounts)
        }
        if draft.counterparty == nil {
            return .reviewRequired(draft, .missingCounterparty)
        }
        return .ready(draft)
    }

    private struct AmountCandidate {
        let amountMinorUnits: Int64
        let position: Int
        let score: Int
    }

    private static func extractAmounts(from text: String) -> (valid: [AmountCandidate], foundInvalid: Bool) {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)(?<![A-Za-z0-9])(?:LKR|Rs\.?)\s*([0-9][0-9,.]*)"#
        ) else { return ([], false) }

        let source = text as NSString
        var candidates: [AmountCandidate] = []
        var foundInvalid = false

        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let raw = source.substring(with: match.range(at: 1))
            let numeric = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            guard let amount = minorUnits(from: numeric) else {
                foundInvalid = true
                continue
            }

            let prefixStart = max(0, match.range.location - 48)
            let prefix = source.substring(with: NSRange(location: prefixStart, length: match.range.location - prefixStart))
            let suffixEnd = min(source.length, NSMaxRange(match.range) + 32)
            let suffix = source.substring(with: NSRange(location: NSMaxRange(match.range), length: suffixEnd - NSMaxRange(match.range)))
            var score = 0
            if contains(#"(?:available|current|closing|remaining)\s+bal(?:ance)?\s*[:=]?\s*$|\b(?:avl|avail)\s*bal\s*[:=]?\s*$"#, in: prefix) {
                score -= 5
            }
            if contains(#"\b(?:debited|charged|spent|paid|credited|received|deposited|transferred|withdrawn|refunded)\b"#, in: String(prefix.suffix(28)) + " " + String(suffix.prefix(28))) {
                score += 2
            }
            candidates.append(AmountCandidate(amountMinorUnits: amount, position: match.range.location, score: score))
        }
        return (candidates, foundInvalid)
    }

    private static func minorUnits(from text: String) -> Int64? {
        guard contains(#"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$"#, in: text) else {
            return nil
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = Int64(parts[0].replacingOccurrences(of: ",", with: "")) else { return nil }
        let cents: Int64
        if parts.count == 2 {
            let fraction = String(parts[1])
            guard let value = Int64(fraction) else { return nil }
            cents = fraction.count == 1 ? value * 10 : value
        } else {
            cents = 0
        }
        let (scaled, overflow) = major.multipliedReportingOverflow(by: 100)
        guard !overflow, scaled <= Int64.max - cents else { return nil }
        let result = scaled + cents
        return result > 0 ? result : nil
    }

    private static func extractCounterparty(from text: String) -> String? {
        for preposition in ["at", "from", "to", "by"] {
            let pattern = #"(?i)\b"# + preposition + #"\s+([A-Za-z][A-Za-z0-9&' -]{1,50}?)(?=\s+(?:on|ref|reference|avail(?:able)?|balance|via|using)\b|[.,;]|$)"#
            guard let capture = firstCapture(pattern, in: text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !capture.isEmpty,
                  !contains(#"^(?:your )?(?:account|a/c|card|atm|bank)(?: [0-9Xx]+)?$"#, in: capture) else { continue }
            return capture
        }
        return nil
    }

    private static func extractReference(from text: String) -> String? {
        firstCapture(#"(?i)\b(?:ref(?:erence)?|txn(?: id)?|transaction id)\s*[:#-]?\s*([A-Za-z0-9/-]{4,32})\b"#, in: text)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range(at: 1).location != NSNotFound else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static func contains(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func fingerprint(for text: String, sender: String?) -> String {
        let normalizedText = text.precomposedStringWithCanonicalMapping
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let normalizedSender = (sender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in (normalizedSender + "\u{1F}" + normalizedText).utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
