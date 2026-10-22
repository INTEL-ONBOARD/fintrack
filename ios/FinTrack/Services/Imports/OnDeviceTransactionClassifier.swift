import CoreML
import Foundation
import NaturalLanguage

struct OnDeviceClassificationResult: Equatable {
    enum Source: String {
        case coreML
        case rules
    }

    let categoryID: UUID
    let categoryName: String
    let confidence: Double
    let languageCode: String?
    let source: Source
}

struct OnDeviceClassifierCorrection: Codable, Equatable {
    let text: String
    let suggestedCategory: String
    let chosenCategory: String
    let recordedAt: Date
}

enum OnDeviceClassifierFeedback {
    static let storageKey = "onDeviceClassifierCorrections"

    static func record(
        text: String,
        suggestion: OnDeviceClassificationResult,
        chosenCategory: FinanceCategory
    ) {
        guard suggestion.categoryID != chosenCategory.id else { return }
        let correction = OnDeviceClassifierCorrection(
            text: text,
            suggestedCategory: suggestion.categoryName,
            chosenCategory: chosenCategory.name,
            recordedAt: .now
        )
        var corrections = load()
        corrections.append(correction)
        if corrections.count > 100 { corrections.removeFirst(corrections.count - 100) }
        if let data = try? JSONEncoder().encode(corrections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func load() -> [OnDeviceClassifierCorrection] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let corrections = try? JSONDecoder().decode([OnDeviceClassifierCorrection].self, from: data) else {
            return []
        }
        return corrections
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct OnDeviceTransactionClassifier {
    private let model: MLModel?

    init() {
        model = Self.loadModel()
    }

    init(model: MLModel?) {
        self.model = model
    }

    func suggest(
        text: String,
        kind: TransactionKind,
        categories: [FinanceCategory]
    ) -> OnDeviceClassificationResult? {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return nil }

        let expectedKind: TransactionKind = kind.isInflow ? .income : .expense
        let available = categories.filter { $0.kind == expectedKind }
        guard !available.isEmpty else { return nil }

        let tokens = Set(Self.tokens(in: cleanedText))
        guard !tokens.isEmpty else { return nil }
        let languageCode = Self.languageCode(for: cleanedText)

        if let modelResult = modelSuggestion(tokens: tokens, categories: available, languageCode: languageCode) {
            return modelResult
        }
        return ruleSuggestion(tokens: tokens, categories: available, languageCode: languageCode)
    }

    private func modelSuggestion(
        tokens: Set<String>,
        categories: [FinanceCategory],
        languageCode: String?
    ) -> OnDeviceClassificationResult? {
        guard let model else { return nil }

        var values: [String: MLFeatureValue] = [:]
        for (index, keyword) in Self.coreMLKeywords.enumerated() {
            values["feature_\(index)"] = MLFeatureValue(double: tokens.contains(keyword) ? 1 : 0)
        }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: values),
              let output = try? model.prediction(from: input),
              let label = output.featureValue(for: "label")?.stringValue,
              let category = categories.first(where: { $0.name.caseInsensitiveCompare(label) == .orderedSame }),
              let probabilities = output.featureValue(for: "probabilities")?.dictionaryValue,
              let confidence = probabilities[label]?.doubleValue,
              confidence >= 0.52 else {
            return nil
        }

        return OnDeviceClassificationResult(
            categoryID: category.id,
            categoryName: category.name,
            confidence: confidence,
            languageCode: languageCode,
            source: .coreML
        )
    }

    private func ruleSuggestion(
        tokens: Set<String>,
        categories: [FinanceCategory],
        languageCode: String?
    ) -> OnDeviceClassificationResult? {
        let scored = categories.map { category in
            let categoryWords = Set(Self.tokens(in: category.name))
            let matchedWords = tokens.intersection(categoryWords.union(Self.aliases(for: category.name)))
            return (category: category, score: matchedWords.count)
        }
        guard let best = scored.max(by: { $0.score < $1.score }), best.score > 0 else { return nil }

        let confidence = min(0.9, 0.55 + (Double(best.score) * 0.1))
        return OnDeviceClassificationResult(
            categoryID: best.category.id,
            categoryName: best.category.name,
            confidence: confidence,
            languageCode: languageCode,
            source: .rules
        )
    }

    private static func loadModel() -> MLModel? {
        guard let url = Bundle.main.url(forResource: "FinTrackTransactionClassifier", withExtension: "mlmodelc") else {
            return nil
        }
        return try? MLModel(contentsOf: url)
    }

    private static func tokens(in text: String) -> [String] {
        let value = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = value
        var result: [String] = []
        tokenizer.enumerateTokens(in: value.startIndex..<value.endIndex) { range, _ in
            result.append(String(value[range]))
            return true
        }
        return result
    }

    private static func languageCode(for text: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.language])
        tagger.string = text
        return tagger.dominantLanguage?.rawValue
    }

    private static func aliases(for categoryName: String) -> Set<String> {
        let name = categoryName.lowercased()
        if name.contains("food") || name.contains("dining") { return ["meal", "restaurant", "cafe", "coffee", "lunch", "dinner"] }
        if name.contains("grocer") { return ["market", "supermarket", "vegetables", "grocery"] }
        if name.contains("transport") { return ["uber", "pickme", "taxi", "fuel", "petrol", "bus", "train", "parking"] }
        if name.contains("shop") { return ["mall", "retail", "store", "purchase"] }
        if name.contains("bill") { return ["electricity", "water", "internet", "phone", "utility", "rent"] }
        if name.contains("health") { return ["hospital", "doctor", "pharmacy", "medicine", "clinic", "dental"] }
        if name.contains("education") { return ["school", "university", "course", "tuition", "exam", "class"] }
        if name.contains("travel") { return ["hotel", "flight", "airline", "ticket", "holiday", "trip"] }
        if name.contains("subscription") { return ["netflix", "spotify", "streaming", "membership", "renewal"] }
        if name.contains("salary") { return ["salary", "payroll", "wages", "employer"] }
        if name.contains("income") { return ["income", "bonus", "freelance", "cashback", "gift"] }
        return []
    }

    private static let coreMLKeywords: [String] = [
        "airline",
        "amazon",
        "and",
        "app",
        "appointment",
        "at",
        "bakery",
        "bill",
        "bonus",
        "book",
        "booking",
        "bread",
        "breakfast",
        "bus",
        "cafe",
        "care",
        "carrefour",
        "cash",
        "cashback",
        "city",
        "class",
        "clinic",
        "clothes",
        "cloud",
        "coffee",
        "course",
        "credited",
        "dental",
        "dialog",
        "dinner",
        "doctor",
        "education",
        "electricity",
        "electronics",
        "employer",
        "exam",
        "expense",
        "fare",
        "fee",
        "flight",
        "food",
        "freelance",
        "fuel",
        "general",
        "gift",
        "groceries",
        "grocery",
        "health",
        "holiday",
        "hospital",
        "hotel",
        "household",
        "income",
        "insurance",
        "interest",
        "internet",
        "keells",
        "lunch",
        "mall",
        "market",
        "meal",
        "medical",
        "medicine",
        "membership",
        "merchant",
        "milk",
        "misc",
        "miscellaneous",
        "monthly",
        "netflix",
        "online",
        "order",
        "other",
        "parking",
        "payment",
        "payroll",
        "personal",
        "petrol",
        "pharmacy",
        "phone",
        "pickme",
        "pizza",
        "prescription",
        "purchase",
        "received",
        "renewal",
        "rent",
        "reservation",
        "restaurant",
        "retail",
        "ride",
        "salary",
        "school",
        "service",
        "shoes",
        "shop",
        "shopping",
        "small",
        "software",
        "spotify",
        "station",
        "stay",
        "storage",
        "store",
        "streaming",
        "subscription",
        "supermarket",
        "takeaway",
        "taxi",
        "ticket",
        "tour",
        "train",
        "transport",
        "travel",
        "trip",
        "tuition",
        "uber",
        "university",
        "unknown",
        "utility",
        "vegetables",
        "visit",
        "wages",
        "water",
    ]
}
