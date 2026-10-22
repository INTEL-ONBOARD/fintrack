import Foundation

struct WidgetSummarySnapshot: Codable, Equatable {
    let incomeMinor: Int64
    let expenseMinor: Int64
    let budgetRemainingMinor: Int64?
    let currency: String
    let updatedAt: Date

    static let empty = WidgetSummarySnapshot(
        incomeMinor: 0,
        expenseMinor: 0,
        budgetRemainingMinor: nil,
        currency: "LKR",
        updatedAt: .now
    )
}

enum WidgetSnapshotStore {
    static let appGroup = "group.app.fintrack.ios"
    private static let key = "fintrack.widget.summary"

    static func load() -> WidgetSummarySnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSummarySnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: WidgetSummarySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }
}
