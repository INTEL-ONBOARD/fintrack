import Foundation

enum FinanceAccountType: String, CaseIterable, Identifiable, Codable {
    case checking
    case savings
    case credit
    case investment
    case loan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .credit: "Credit"
        case .investment: "Investment"
        case .loan: "Loan"
        }
    }
}

struct FinanceAccount: Identifiable, Equatable {
    var id: UUID
    var serverID: String?
    var name: String
    var type: FinanceAccountType
    var balanceMinor: Int64
    var limitMinor: Int64
    var color: String
    var bank: String

    init(
        id: UUID = UUID(), serverID: String? = nil, name: String,
        type: FinanceAccountType = .checking, balanceMinor: Int64 = 0,
        limitMinor: Int64 = 0, color: String = "#2E9D68", bank: String = ""
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.type = type
        self.balanceMinor = balanceMinor
        self.limitMinor = limitMinor
        self.color = color
        self.bank = bank
    }
}

struct FinanceGoal: Identifiable, Equatable {
    var id: UUID
    var serverID: String?
    var name: String
    var icon: String
    var targetMinor: Int64
    var currentMinor: Int64
    var color: String
    var deadline: String

    init(
        id: UUID = UUID(), serverID: String? = nil, name: String,
        icon: String = "target", targetMinor: Int64, currentMinor: Int64 = 0,
        color: String = "#2E9D68", deadline: String = ""
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.icon = icon
        self.targetMinor = targetMinor
        self.currentMinor = currentMinor
        self.color = color
        self.deadline = deadline
    }
}

struct FinanceBill: Identifiable, Equatable {
    var id: UUID
    var serverID: String?
    var name: String
    var amountMinor: Int64
    var dueDay: Int
    var category: String
    var color: String
    var paid: Bool

    init(
        id: UUID = UUID(), serverID: String? = nil, name: String,
        amountMinor: Int64, dueDay: Int = 1, category: String = "Bills",
        color: String = "#4886D2", paid: Bool = false
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.amountMinor = amountMinor
        self.dueDay = dueDay
        self.category = category
        self.color = color
        self.paid = paid
    }
}

enum FinanceNotificationType: String, CaseIterable, Identifiable, Codable {
    case alert
    case info
    case success

    var id: String { rawValue }
}

struct FinanceNotification: Identifiable, Equatable {
    var id: UUID
    var serverID: String?
    var title: String
    var body: String
    var time: String
    var read: Bool
    var type: FinanceNotificationType

    init(
        id: UUID = UUID(), serverID: String? = nil, title: String, body: String,
        time: String = "", read: Bool = false, type: FinanceNotificationType = .info
    ) {
        self.id = id
        self.serverID = serverID
        self.title = title
        self.body = body
        self.time = time
        self.read = read
        self.type = type
    }
}

struct FinanceUserSettings: Codable, Equatable {
    var name: String
    var email: String
    var currency: String
    var notifications: [String: Bool]

    init(name: String = "", email: String = "", currency: String = "LKR", notifications: [String: Bool] = [:]) {
        self.name = name
        self.email = email
        self.currency = currency
        self.notifications = notifications
    }
}
