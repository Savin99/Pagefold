import Foundation
import Security

/// Простое хранилище секретов в Keychain. Здесь живёт API-ключ Anthropic.
enum KeychainStore {
    private static let service = "com.integra4d.pagefold"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        get { read() }
        set {
            if let value = newValue, !value.isEmpty {
                write(value)
            } else {
                delete()
            }
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery()
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
