import Foundation

struct ReceiptCalendarDate: Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int
}

enum ReceiptIssue: Equatable, Sendable {
    case missingMerchant
    case missingDate
    case missingTotal
    case ambiguousTotal
    case unsupportedCurrency
}

struct ReceiptDraft: Equatable, Sendable {
    let merchant: String?
    let date: ReceiptCalendarDate?
    let totalMinorUnits: Int64?
    let currencyCode: String
    let issues: [ReceiptIssue]
}

enum ReceiptParser {
    static func parse(_ recognizedText: String) -> ReceiptDraft {
        let lines = recognizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let merchant = findMerchant(in: lines)
        let date = findDate(in: lines)
        let total = findTotal(in: lines)
        var issues: [ReceiptIssue] = []
        if merchant == nil { issues.append(.missingMerchant) }
        if date == nil { issues.append(.missingDate) }
        if total.amount == nil { issues.append(.missingTotal) }
        if total.ambiguous { issues.append(.ambiguousTotal) }
        if total.unsupportedCurrency { issues.append(.unsupportedCurrency) }

        return ReceiptDraft(
            merchant: merchant,
            date: date,
            totalMinorUnits: total.unsupportedCurrency ? nil : total.amount,
            currencyCode: "LKR",
            issues: issues
        )
    }

    private static func findMerchant(in lines: [String]) -> String? {
        var firstMatch: String?
        for line in lines.prefix(14) {
            guard line.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil else { continue }
            if contains(#"^(?:tax )?(?:receipt|invoice|bill)(?:\s*(?:no|number|#).*|\s*)$|^thank you\b|^(?:fn|control|option|command|shift|alt)$|\b(?:p?roperty of|copyright|all rights reserved|date|time|total|subtotal|amount due|vat|tax|phone|tel|email|www\.|http)\b"#, in: line) {
                continue
            }
            let cleaned = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            if cleaned.isEmpty { continue }
            if contains(#"\b(?:store|super|mart|cafe|coffee|restaurant|filling station|highway|pvt|ltd)\b"#, in: cleaned) {
                return cleaned
            }
            if firstMatch == nil { firstMatch = cleaned }
        }
        return firstMatch
    }

    private static func findDate(in lines: [String]) -> ReceiptCalendarDate? {
        let ordered = lines.filter { contains(#"\b(?:date|issued|purchased)\b"#, in: $0) }
            + lines.filter { !contains(#"\b(?:date|issued|purchased)\b"#, in: $0) }
        for line in ordered {
            if let date = parseDate(in: line) { return date }
        }
        return nil
    }

    private static func parseDate(in line: String) -> ReceiptCalendarDate? {
        if let values = captures(#"(?<![0-9])([0-9]{4})[-/.]([0-9]{1,2})[-/.]([0-9]{1,2})(?![0-9])"#, in: line),
           let year = Int(values[0]), let month = Int(values[1]), let day = Int(values[2]) {
            return validDate(year: year, month: month, day: day)
        }
        if let values = captures(#"(?<![0-9])([0-9]{1,2})[-/.]([0-9]{1,2})[-/.]([0-9]{4})(?![0-9])"#, in: line),
           let day = Int(values[0]), let month = Int(values[1]), let year = Int(values[2]) {
            return validDate(year: year, month: month, day: day)
        }
        return nil
    }

    private static func validDate(year: Int, month: Int, day: Int) -> ReceiptCalendarDate? {
        guard (2000...2100).contains(year) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let value = calendar.date(from: components) else { return nil }
        let checked = calendar.dateComponents([.year, .month, .day], from: value)
        guard checked.year == year, checked.month == month, checked.day == day else { return nil }
        return ReceiptCalendarDate(year: year, month: month, day: day)
    }

    private struct TotalCandidate {
        let amount: Int64
        let score: Int
        let lineIndex: Int
        let unsupportedCurrency: Bool
    }

    private static func findTotal(in lines: [String]) -> (amount: Int64?, ambiguous: Bool, unsupportedCurrency: Bool) {
        var candidates: [TotalCandidate] = []
        for (index, line) in lines.enumerated() {
            if contains(#"\b(?:sub\s*total|total (?:items|discount|tax|vat)|tax total)\b"#, in: line) { continue }

            let score: Int
            if contains(#"\bgrand total\b"#, in: line) { score = 4 }
            else if contains(#"\b(?:amount payable|amount due|total due|net total)\b"#, in: line) { score = 3 }
            else if contains(#"\b(?:total|amount)\b|\brs\.?\s*\(\s*lkr\s*\)"#, in: line) { score = 2 }
            else { continue }

            let amountSection: String
            if let label = line.range(of: #"(?i)\b(?:grand total|amount payable|amount due|total due|net total|total|amount)\b|\brs\.?\s*\(\s*lkr\s*\)"#, options: .regularExpression) {
                amountSection = String(line[label.upperBound...])
            } else {
                continue
            }
            let nextLine = index + 1 < lines.count ? lines[index + 1] : ""
            let amountText = amountSection.range(of: #"[0-9]"#, options: .regularExpression) == nil &&
                contains(#"\b(?:LKR|Rs\.?)\b"#, in: nextLine) ? nextLine : amountSection
            guard let rawAmount = captures(#"(?i)(?:LKR|Rs\.?)?\s*([0-9][0-9,.]*)"#, in: amountText)?.first,
                  let amount = minorUnits(from: rawAmount.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))) else {
                continue
            }
            let foreignCurrency = contains(#"\b(?:USD|EUR|GBP|INR|AUD|CAD)\b|[$€£₹]"#, in: line)
            candidates.append(TotalCandidate(amount: amount, score: score, lineIndex: index, unsupportedCurrency: foreignCurrency))
        }

        guard let bestScore = candidates.map(\.score).max() else { return (nil, false, false) }
        let strongest = candidates.filter { $0.score == bestScore }
        let selected = strongest.max { $0.lineIndex < $1.lineIndex }!
        return (selected.amount, Set(strongest.map(\.amount)).count > 1, selected.unsupportedCurrency)
    }

    private static func minorUnits(from text: String) -> Int64? {
        guard contains(#"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$"#, in: text) else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = Int64(parts[0].replacingOccurrences(of: ",", with: "")) else { return nil }
        let fraction: Int64
        if parts.count == 2 {
            guard let value = Int64(parts[1]) else { return nil }
            fraction = parts[1].count == 1 ? value * 10 : value
        } else {
            fraction = 0
        }
        let (scaled, overflow) = major.multipliedReportingOverflow(by: 100)
        guard !overflow, scaled <= Int64.max - fraction else { return nil }
        let result = scaled + fraction
        return result > 0 ? result : nil
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let source = text as NSString
        return (1..<match.numberOfRanges).map { source.substring(with: match.range(at: $0)) }
    }

    private static func contains(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
