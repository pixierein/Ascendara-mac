import Foundation
import Security

enum KeychainService {
    private static let Service = "app.ascendara.native"

    static func Read(_ Key: String) -> String? {
        let Query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Service,
            kSecAttrAccount as String: Key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var Result: CFTypeRef?
        guard SecItemCopyMatching(Query as CFDictionary, &Result) == errSecSuccess,
              let Data = Result as? Data else { return nil }
        return String(data: Data, encoding: .utf8)
    }

    static func Write(_ Value: String, For Key: String) throws {
        let Query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Service,
            kSecAttrAccount as String: Key
        ]
        if Value.isEmpty {
            let Status = SecItemDelete(Query as CFDictionary)
            guard Status == errSecSuccess || Status == errSecItemNotFound else { throw Failure(Status) }
            return
        }
        let Data = Data(Value.utf8)
        var Status = SecItemUpdate(Query as CFDictionary, [kSecValueData as String: Data] as CFDictionary)
        if Status == errSecItemNotFound {
            var Item = Query
            Item[kSecValueData as String] = Data
            Item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            Status = SecItemAdd(Item as CFDictionary, nil)
        }
        guard Status == errSecSuccess else { throw Failure(Status) }
    }

    private static func Failure(_ Status: OSStatus) -> AppFailure {
        .Message("Keychain: \(SecCopyErrorMessageString(Status, nil) as String? ?? String(Status))")
    }
}
