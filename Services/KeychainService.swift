import Foundation
import Security

/// A service for securely storing sensitive credentials in the iOS Keychain
class KeychainService {

    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case encodingError
        case decodingError

        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .itemNotFound:
                return "Item not found in Keychain"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .encodingError:
                return "Failed to encode data for Keychain"
            case .decodingError:
                return "Failed to decode data from Keychain"
            }
        }
    }

    // MARK: - Keychain Keys

    enum Key: String {
        case syncServerURL = "com.dulcinea.sync.serverURL"
        case syncUsername = "com.dulcinea.sync.username"
        case syncPassword = "com.dulcinea.sync.password"
        case opdsCatalogCredentials = "com.dulcinea.opds.credentials"
    }

    // MARK: - Generic Keychain Operations

    /// Save a string value to the Keychain
    func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingError
        }
        try save(data, for: key.rawValue)
    }

    /// Retrieve a string value from the Keychain
    func getString(for key: Key) throws -> String? {
        guard let data = try getData(for: key.rawValue) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingError
        }
        return string
    }

    /// Delete a value from the Keychain
    func delete(key: Key) throws {
        try delete(for: key.rawValue)
    }

    // MARK: - Sync Configuration

    /// Save sync configuration credentials securely
    func saveSyncCredentials(serverURL: String, username: String, password: String) throws {
        try save(serverURL, for: .syncServerURL)
        try save(username, for: .syncUsername)
        try save(password, for: .syncPassword)
    }

    /// Load sync configuration credentials
    func loadSyncCredentials() -> (serverURL: String, username: String, password: String)? {
        do {
            guard let serverURL = try getString(for: .syncServerURL),
                  let username = try getString(for: .syncUsername),
                  let password = try getString(for: .syncPassword) else {
                return nil
            }
            return (serverURL, username, password)
        } catch {
            print("Failed to load sync credentials: \(error)")
            return nil
        }
    }

    /// Delete all sync credentials
    func deleteSyncCredentials() {
        try? delete(key: .syncServerURL)
        try? delete(key: .syncUsername)
        try? delete(key: .syncPassword)
    }

    // MARK: - OPDS Catalog Credentials

    /// Save OPDS catalog credentials (stored as JSON dictionary keyed by catalog ID)
    func saveOPDSCredentials(catalogId: UUID, username: String, password: String) throws {
        var credentials = loadAllOPDSCredentials()
        credentials[catalogId.uuidString] = OPDSCredential(username: username, password: password)

        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        try save(data, for: Key.opdsCatalogCredentials.rawValue)
    }

    /// Load OPDS catalog credentials for a specific catalog
    func loadOPDSCredentials(for catalogId: UUID) -> (username: String, password: String)? {
        let credentials = loadAllOPDSCredentials()
        guard let credential = credentials[catalogId.uuidString] else {
            return nil
        }
        return (credential.username, credential.password)
    }

    /// Delete OPDS catalog credentials
    func deleteOPDSCredentials(for catalogId: UUID) {
        var credentials = loadAllOPDSCredentials()
        credentials.removeValue(forKey: catalogId.uuidString)

        if credentials.isEmpty {
            try? delete(key: .opdsCatalogCredentials)
        } else {
            if let data = try? JSONEncoder().encode(credentials) {
                try? save(data, for: Key.opdsCatalogCredentials.rawValue)
            }
        }
    }

    private func loadAllOPDSCredentials() -> [String: OPDSCredential] {
        guard let data = try? getData(for: Key.opdsCatalogCredentials.rawValue),
              let credentials = try? JSONDecoder().decode([String: OPDSCredential].self, from: data) else {
            return [:]
        }
        return credentials
    }

    // MARK: - Private Keychain Operations

    private func save(_ data: Data, for key: String) throws {
        // First try to delete any existing item
        try? delete(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func getData(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Supporting Types

private struct OPDSCredential: Codable {
    let username: String
    let password: String
}
