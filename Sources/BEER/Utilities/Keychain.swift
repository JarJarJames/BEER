import Foundation
import Security

// Minimal wrapper over the macOS login Keychain for storing a single secret
// blob (a generic-password item). Used for the Steam refresh token, which is a
// real credential: keeping it here means it's encrypted at rest and gated on
// the user's login, instead of sitting in a readable JSON file under
// Application Support where a targeted stealer could grab it.
//
// We use the classic (file-based) keychain on purpose — it needs no entitlement
// and works for an ad-hoc-signed, non-sandboxed app. Items live in the user's
// login keychain and are scoped to this Mac (they don't sync to iCloud).
enum Keychain {
    /// Service identifier all BEER keychain items share. Older builds (named
    /// "GameNativeMac") used `legacyService`; see `SteamAuthStore.load()` for
    /// the one-time migration.
    static let defaultService = "io.github.jarjarjames.beer"
    static let legacyService = "com.gamenative.mac"

    /// Store (or replace) the secret blob for `account`.
    static func set(_ data: Data, account: String, service: String = defaultService) throws {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = match
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Read the secret blob for `account`, or nil if absent.
    static func get(account: String, service: String = defaultService) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Remove the secret blob for `account` (no-op if absent).
    static func delete(account: String, service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
