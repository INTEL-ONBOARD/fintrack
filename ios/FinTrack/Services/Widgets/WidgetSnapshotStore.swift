import Foundation
import Security

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
    private static let keychainService = "app.fintrack.widget.summary"

    private static var keychainGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainAccessGroup") as? String,
              !group.contains("$("), !group.isEmpty else { return nil }
        return group
    }

    static func load() -> WidgetSummarySnapshot? {
        if let group = keychainGroup {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: key,
                kSecAttrAccessGroup as String: group,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let snapshot = try? JSONDecoder().decode(WidgetSummarySnapshot.self, from: data) {
                return snapshot
            }
        }
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSummarySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: WidgetSummarySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let group = keychainGroup {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: key,
                kSecAttrAccessGroup as String: group
            ]
            let changes: [String: Any] = [kSecValueData as String: data]
            if SecItemUpdate(query as CFDictionary, changes as CFDictionary) == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(item as CFDictionary, nil)
            }
        }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }
}
