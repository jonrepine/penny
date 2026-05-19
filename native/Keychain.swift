import Foundation
import Security

/// Stores per-provider API keys in the macOS Keychain under service
/// `penny`. The Python helper reads the same entries via the
/// `keyring` package.
enum Keychain {
    private static let service = "penny"

    static func read(account: String) -> String? {
        // `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail` tells the
        // Security framework to return an error instead of putting up a
        // confirmation prompt when our app isn't on the item's ACL. Without
        // this, the call blocks forever in an accessory-policy daemon
        // because the prompt has no visible window to attach to.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                log("Keychain.read: existing item for \(account) is not accessible to this build. " +
                    "Delete and re-enter via Preferences.")
            }
            return nil
        }
        return string
    }

    @discardableResult
    static func write(account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            log("Keychain update failed for \(account): \(updateStatus)")
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log("Keychain add failed for \(account): \(addStatus)")
            return false
        }
        return true
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
