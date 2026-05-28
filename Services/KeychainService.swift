import Foundation
import Security

class KeychainService {

    private enum KeychainKey {
        static let syncServerURL = "com.dulcinea.sync.serverURL"
        static let syncUsername = "com.dulcinea.sync.username"
        static let syncPassword = "com.dulcinea.sync.password"

        static func opdsUsername(for catalogId: UUID) -> String {
            "com.dulcinea.opds.\(catalogId.uuidString).username"
        }
        static func opdsPassword(for catalogId: UUID) -> String {
            "com.dulcinea.opds.\(catalogId.uuidString).password"
        }
    }

    // MARK: - Sync Credentials

    func saveSyncCredentials(serverURL: String, username: String, password: String) throws {
        try set(value: serverURL, forKey: KeychainKey.syncServerURL)
        try set(value: username, forKey: KeychainKey.syncUsername)
        try set(value: password, forKey: KeychainKey.syncPassword)
    }

    func loadSyncCredentials() -> (serverURL: String, username: String, password: String)? {
        guard let serverURL = get(forKey: KeychainKey.syncServerURL),
              let username = get(forKey: KeychainKey.syncUsername),
              let password = get(forKey: KeychainKey.syncPassword) else {
            return nil
        }
        return (serverURL, username, password)
    }

    func deleteSyncCredentials() {
        delete(forKey: KeychainKey.syncServerURL)
        delete(forKey: KeychainKey.syncUsername)
        delete(forKey: KeychainKey.syncPassword)
    }

    // MARK: - OPDS Catalog Credentials

    func saveOPDSCredentials(catalogId: UUID, username: String, password: String) throws {
        try set(value: username, forKey: KeychainKey.opdsUsername(for: catalogId))
        try set(value: password, forKey: KeychainKey.opdsPassword(for: catalogId))
    }

    func loadOPDSCredentials(for catalogId: UUID) -> (username: String, password: String)? {
        guard let username = get(forKey: KeychainKey.opdsUsername(for: catalogId)),
              let password = get(forKey: KeychainKey.opdsPassword(for: catalogId)) else {
            return nil
        }
        return (username, password)
    }

    func deleteOPDSCredentials(for catalogId: UUID) {
        delete(forKey: KeychainKey.opdsUsername(for: catalogId))
        delete(forKey: KeychainKey.opdsPassword(for: catalogId))
    }

    // MARK: - Keychain Helpers

    private func set(value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete any existing item first
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for Keychain storage"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        }
    }
}
