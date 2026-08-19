import Foundation

// MARK: - 设备身份与展示名（M1d：移植 Rhino 线 AhaKeyDeviceIdentity）
//
// 纯函数：BLE 名匹配、序列号 → 4 位设备编号、广播 manufacturer data → 设备编号。
// AhaKeyBLEManager 与设备信息页共用，保证扫描/详情/日志里的身份口径一致。

public enum AhaKeyDevicePresentation {
    /// BLE 名前缀：旧固件广播 "AhaKey"，新固件广播 "AhaKey X1"，前缀匹配同时覆盖两者。
    public static let bleNamePrefix = "AhaKey"

    public static let systemName = "AhaKey X1"
    public static let navigationName = "AhaKey-X1"
    public static let modelName = "AhaKey X1"

    /// 广播名/连接名是否属于 AhaKey 设备（大小写不敏感前缀匹配）。
    public static func matchesBLEName(_ name: String) -> Bool {
        name.lowercased().hasPrefix(bleNamePrefix.lowercased())
    }

    /// 从 USB/BLE 序列号提取 4 位设备编号，兼容两种格式：
    /// - 旧格式 "505C-AABBCCDDEEFF"：前缀即编号；
    /// - 新格式 "AHX1-C0F55C506C54889A"：取 UID 第 3、4 字节（小端序拼接，如 "505C"）。
    /// 无法识别时返回 nil。
    public static func shortIdentifier(from serialNumber: String) -> String? {
        let components = serialNumber.uppercased().split(separator: "-", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }
        if components[0].count == 4, components[0] != "AHX1" {
            return components[0]
        }
        let uid = components[1]
        guard components[0] == "AHX1", uid.count >= 8 else { return nil }
        let byte2 = uid.index(uid.startIndex, offsetBy: 4) ..< uid.index(uid.startIndex, offsetBy: 6)
        let byte3 = uid.index(uid.startIndex, offsetBy: 6) ..< uid.index(uid.startIndex, offsetBy: 8)
        return String(uid[byte3] + uid[byte2])
    }

    /// 从 BLE 广播 manufacturer data 提取 4 位设备编号
    ///（固件在 advertData +14 处写入 4 字节 ASCII 十六进制编号，前 5 字节为固定标识头）。
    public static func advertisedIdentifier(manufacturerData: Data?) -> String? {
        guard let manufacturerData, manufacturerData.count >= 9 else { return nil }
        let prefix = Array(manufacturerData.prefix(5))
        guard prefix == [0x06, 0x00, 0x03, 0x00, 0x80] else { return nil }
        let suffix = manufacturerData.subdata(in: 5 ..< 9)
        guard let identifier = String(data: suffix, encoding: .ascii),
              identifier.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return identifier.uppercased()
    }

    /// 旧固件的 BLE 名后缀即设备编号（"AhaKey 515C" → "515C"，固件把 MAC 后 4 位拼在名后）。
    /// 新固件 "AhaKey X1" 无编号后缀、未个性化设备残留逗号占位（"AhaKey ,,,,"），均返回 nil。
    public static func nameSuffixIdentifier(_ name: String) -> String? {
        let parts = name.split(separator: " ")
        guard parts.count == 2, parts[0].lowercased() == "ahakey" else { return nil }
        let suffix = parts[1]
        guard suffix.count == 4, suffix.allSatisfy({ $0.isHexDigit }) else { return nil }
        return suffix.uppercased()
    }

    /// 多设备选择场景的设备编号副标题；单设备且无需消歧时不显示。
    public static func selectionSubtitle(identifier: String, deviceCount: Int, needsDisambiguation: Bool = false) -> String? {
        guard identifier != "—", deviceCount > 1 || needsDisambiguation else { return nil }
        return "设备编号 \(identifier)"
    }

    /// 日志/诊断统一身份标签："AhaKey X1 / 505C / AHX1-…"。
    public static func diagnosticLabel(identifier: String, serialNumber: String? = nil) -> String {
        let serial = serialNumber?.isEmpty == false ? serialNumber! : "—"
        return "\(systemName) / \(identifier) / \(serial)"
    }
}
