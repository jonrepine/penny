import Foundation
import LocalAuthentication
import Security

/// Stores per-provider API keys in the macOS Keychain under service `penny`.
/// One entry per provider (account = "anthropic" / "openai" / "gemini").
///
/// Only the Swift side touches Keychain. The Python helper reads keys from
/// process environment variables that Swift passes when spawning it, so the
/// user only sees the "Always Allow" Keychain prompt once.
enum Keychain {
    private static let service = "penny"

    /// Read a stored API key for `account`, returning nil if missing or if the
    /// item's ACL doesn't include this binary. We block UI confirmation
    /// prompts because there's no window to attach them to in an
    /// accessory-policy daemon — without this, the call would hang forever.
    static func read(account: String) -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                log("Keychain.read: existing item for \(account) is not accessible to this build. Delete and re-enter via Preferences.")
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
