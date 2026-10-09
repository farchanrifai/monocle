import Foundation
import Security

/// The user's own Anthropic API key, kept in the Keychain on this device only.
// ponytail: personal-key mode for SideStore testing; a proxy replaces this before anyone else uses chat (CHAT_SPEC §8).
enum APIKeyStore {
    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.farchan.monocle.anthropic",
         kSecAttrAccount as String: "api-key"]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var request = query()
        request[kSecReturnData as String] = true
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var request = query()
        request[kSecValueData as String] = Data(key.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query() as CFDictionary)
    }
}
