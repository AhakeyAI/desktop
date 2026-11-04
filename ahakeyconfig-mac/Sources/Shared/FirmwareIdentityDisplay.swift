import Foundation

/// Display-only device identity. A catalog key identifies a protocol contract,
/// not the hash of the running HEX, and never grants configuration authority.
public enum FirmwareIdentityDisplay {
    public static func validKey(_ value: Any?) -> String? {
        guard let key = value as? String, !key.isEmpty, key.utf8.count <= 128,
              key.utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { return nil }
        return key
    }

    public static func catalogKey(from frame: Data) -> String? {
        let bytes = [UInt8](frame)
        guard bytes.count >= 7, bytes.count <= 134,
              Array(bytes.prefix(4)) == [0xAA, 0xBB, 0x9F, 0],
              Array(bytes.suffix(2)) == [0xCC, 0xDD] else { return nil }
        return validKey(String(bytes: bytes[4..<(bytes.count - 2)], encoding: .ascii))
    }

    public static func label(catalogKey: String?, statusVersion: String?) -> String? {
        guard let key = validKey(catalogKey) else { return statusVersion }
        guard let range = key.range(of: "[0-9]+\\.[0-9]+\\.[0-9]+-r[0-9]+$", options: .regularExpression) else { return key }
        return String(key[range])
    }
}
