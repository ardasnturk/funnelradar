import Foundation
import Security

public enum KeychainAccount {
    private static let service = "com.jastech.funnelradar.service-account"
    private static let account = "service-account"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public static func read() -> ServiceAccount? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ServiceAccount.self, from: data)
    }

    public static func save(_ value: ServiceAccount) throws {
        delete()
        var attributes = query
        attributes[kSecValueData as String] = try JSONEncoder().encode(value)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw FunnelError.failed("The Keychain refused the secret (\(status)).") }
    }

    public static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
