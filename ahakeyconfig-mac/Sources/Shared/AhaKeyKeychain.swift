import Foundation
import Security

/// 钥匙串访问帮助类，用于安全存储令牌、密码等敏感信息。
///
/// 所有条目都使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，
/// 保证设备重启后、首次解锁前无法读取，且不会随 iCloud 同步。
public enum AhaKeyKeychain {
    public enum Error: Swift.Error {
        case addFailed(OSStatus)
        case deleteFailed(OSStatus)
    }

    /// 将字符串安全地保存到钥匙串。同一 service/account 已存在时会先覆盖。
    public static func save(service: String, account: String, value: String) throws {
        let data = Data(value.utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Error.addFailed(status)
        }
    }

    /// 从钥匙串读取指定 service/account 的字符串值。
    public static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从钥匙串删除指定 service/account 的条目。
    @discardableResult
    public static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
