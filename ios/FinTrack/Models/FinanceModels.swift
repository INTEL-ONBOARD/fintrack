import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income
    case transfer
    case refund
    case cashWithdrawal = "cash_withdrawal"
    case bankFee = "bank_fee"
    case interest
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        case .refund: "Refund"
        case .cashWithdrawal: "Cash withdrawal"
        case .bankFee: "Bank fee"
        case .interest: "Interest"
        case .other: "Other"
        }
    }

    var isOutflow: Bool { self == .expense || self == .bankFee }
    var isInflow: Bool { self == .income || self == .interest }
}

enum TransactionSource: String, Codable {
    case manual, sms, receipt, siri, voice
}

struct FinanceTransaction: Identifiable, Equatable, Codable {
    var id: UUID
    var kind: TransactionKind
    var amountMinor: Int64
    var currency: String
    var occurredAt: Date
    var categoryID: UUID?
    var merchant: String
    var note: String
    var tags: [String]
    var paymentMethod: String
    var source: TransactionSource
    var externalReference: String?
    var latitude: Double?
    var longitude: Double?
    var locationName: String?

    init(
        id: UUID = UUID(), kind: TransactionKind, amountMinor: Int64,
        currency: String = "LKR", occurredAt: Date = .now,
        categoryID: UUID? = nil, merchant: String = "", note: String = "",
        tags: [String] = [], paymentMethod: String = "", source: TransactionSource = .manual,
        externalReference: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
        locationName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.amountMinor = amountMinor
        self.currency = currency
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.tags = tags
        self.paymentMethod = paymentMethod
        self.source = source
        self.externalReference = externalReference
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
    }
}

struct FinanceCategory: Identifiable, Equatable {
    var id: UUID
    var serverID: String?
    var name: String
    var kind: TransactionKind
    var color: String
    var needsSync: Bool
    init(
        id: UUID = UUID(), serverID: String? = nil, name: String,
        kind: TransactionKind, color: String = "#151718", needsSync: Bool = true
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.kind = kind
        self.color = color
        self.needsSync = needsSync
    }
}

struct FinanceBudget: Identifiable, Equatable {
    var id: UUID
    var serverID: String?
    var month: String
    var categoryID: UUID?
    var amountMinor: Int64
    var currency: String
    var needsSync: Bool
    init(
        id: UUID = UUID(), serverID: String? = nil, month: String,
        categoryID: UUID? = nil, amountMinor: Int64, currency: String = "LKR",
        needsSync: Bool = true
    ) {
        self.id = id
        self.serverID = serverID
        self.month = month
        self.categoryID = categoryID
        self.amountMinor = amountMinor
        self.currency = currency
        self.needsSync = needsSync
    }
}
