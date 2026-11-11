import Foundation
import Security

/// API keys for Call Assist, one generic-password item per provider.
enum KeychainStore {
    private static let service = "Lafz.CallAssist"

    static func key(for provider: AssistProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String, for provider: AssistProvider) throws {
        delete(for: provider)
        var item = baseQuery(provider)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete(for provider: AssistProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
    }

    private static func baseQuery(_ provider: AssistProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Could not save the key to the Keychain: \(message)"
    }
}
