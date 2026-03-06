import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.claudeusagemonitor.app"
    private let account = "oauth-tokens"
    private var cachedTokens: OAuthTokens?

    private init() {}

    func saveTokens(_ tokens: OAuthTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        let lookupQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        var status = SecItemUpdate(lookupQuery as CFDictionary,
                                   [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            let addQuery: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecValueData:   data
            ]
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if status == errSecSuccess { cachedTokens = tokens }
        return status == errSecSuccess
    }

    func getTokens() -> OAuthTokens? {
        if let cached = cachedTokens { return cached }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data   = result as? Data,
              let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data)
        else { return nil }
        cachedTokens = tokens
        return tokens
    }

    func deleteTokens() {
        cachedTokens = nil
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
