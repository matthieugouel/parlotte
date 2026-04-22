import Foundation
import Security

/// Thin wrapper over the macOS Keychain for storing per-profile secrets
/// (access tokens, refresh tokens). Items are scoped to the app bundle via
/// `kSecAttrService` and per-profile via `kSecAttrAccount`, and are marked
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so they never leave the
/// device in an iCloud backup or via migration.
public enum ParlotteKeychain {
    private static let service = "dev.nxthdr.Parlotte"

    /// Store `value` under `account`. Overwrites any existing entry.
    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)

        // SecItemUpdate first so we don't clobber the ACL if something
        // has pre-set one. Fall back to SecItemAdd if nothing is there.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    public static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    @discardableResult
    public static func remove(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
