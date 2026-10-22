import Foundation
import Security

struct KeychainStore {
    private let service = "app.fintrack.ios.auth"

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw KeychainError.saveFailed
            }
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed
        }
    }

    func read(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.readFailed
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed
    case readFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed: "FinTrack could not save the secure login details."
        case .readFailed: "FinTrack could not read the secure login details."
        case .deleteFailed: "FinTrack could not clear the secure login details."
        }
    }
}
