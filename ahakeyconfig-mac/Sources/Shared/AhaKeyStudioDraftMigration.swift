import Foundation

/// 草稿持久化双 schema 迁移（纯函数，不依赖 Models 层，便于单测）。
///
/// 背景：`ahakey.studio.draft.v1` 这个 UserDefaults key 被主线（main）与 Rhino 两版
/// app 共用，两版写出的 OLED 草稿 JSON 结构不同。统一版加载草稿前先把 JSON 归一化为
/// 统一格式（双套 × 4 态），再交给 Codable 解码。
///
/// 判定逻辑（schema 版本字段优先，无版本字段时按结构特征判别），逐 mode 的 `oled` 对象判定：
/// - 含 `taskGIFSets`：Rhino / 统一格式（双套）。`taskGIFSchemaVersion` 缺失按 0 处理；
///   schema < 2 且套图 B 与套图 A 完全相等时清空套图 B（Rhino schema 1 曾把默认动画复制进 B）。
/// - 否则含 `taskGIFAssets`：主线格式（3 态单套）。单套进套图 A，idle 回退 working 图
///   （Rhino 语义），套图 B 初始为空，schema 记 0。
/// - 两者皆无：更老的"仅默认动画"格式。按 localAssetPath 种子套图 A 的 done 槽，其余同上。
///
/// 迁移只重写 `oled` 对象内的任务图字段；键位（keys）、灯效（lightBar）、状态行
/// （statusLine）、默认动画路径（localAssetPath）等一律原样保留。
public enum AhaKeyStudioDraftMigration {
    /// 单个 OLED 草稿对象的存储格式。
    public enum OLEDFormat: String, Equatable, Sendable {
        /// Rhino / 统一：双套 taskGIFSets。
        case dualSet
        /// 主线：3 态单套 taskGIFAssets。
        case legacySingleSet
        /// 更老：仅 localAssetPath 默认动画，无任务图。
        case legacyDefaultOnly
    }

    public static let taskGIFSchemaVersionLegacy = 0

    /// 判别一个 OLED 草稿对象的格式。
    public static func detectOLEDFormat(_ oled: [String: Any]) -> OLEDFormat {
        if oled["taskGIFSets"] != nil { return .dualSet }
        if oled["taskGIFAssets"] != nil { return .legacySingleSet }
        return .legacyDefaultOnly
    }

    /// 把任意历史格式的草稿 JSON 归一化为统一格式（双套 × 4 态）。
    /// 输入不是合法 JSON 对象或缺少 modes 数组时返回 nil（调用方按原样解码/放弃）。
    /// 输出可再次传入本函数，结果不变（幂等）。
    public static func migrateDraftData(_ data: Data) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              var dict = root as? [String: Any],
              let modes = dict["modes"] as? [[String: Any]]
        else { return nil }
        dict["modes"] = modes.map { migrateMode($0) }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    // MARK: - 内部实现

    private static func migrateMode(_ mode: [String: Any]) -> [String: Any] {
        var mode = mode
        guard let oled = mode["oled"] as? [String: Any] else { return mode }
        mode["oled"] = migrateOLED(oled)
        return mode
    }

    private static func migrateOLED(_ oled: [String: Any]) -> [String: Any] {
        switch detectOLEDFormat(oled) {
        case .dualSet:
            return migrateDualSetOLED(oled)
        case .legacySingleSet, .legacyDefaultOnly:
            return migrateLegacyOLED(oled)
        }
    }

    /// Rhino / 统一格式：字段原样保留，只套用 schema < 2 的套图 B 去重规则并补齐缺省字段。
    private static func migrateDualSetOLED(_ oled: [String: Any]) -> [String: Any] {
        var oled = oled
        let schema = (oled["taskGIFSchemaVersion"] as? Int) ?? 0
        oled["taskGIFSchemaVersion"] = schema
        oled["activeGIFSet"] = (oled["activeGIFSet"] as? Int) ?? 0
        guard var sets = oled["taskGIFSets"] as? [[String: Any]] else { return oled }
        if schema < 2, sets.count > 1,
           let setA = sets[0]["assets"] as? [[String: Any]],
           let setB = sets[1]["assets"] as? [[String: Any]],
           assetsEqualIgnoringOrder(setA, setB)
        {
            sets[1] = ["assets": emptyAssets()]
        }
        oled["taskGIFSets"] = sets
        return oled
    }

    /// 主线 / 更老格式：单套（或仅默认动画）迁入套图 A，套图 B 为空，schema 记 0。
    private static func migrateLegacyOLED(_ oled: [String: Any]) -> [String: Any] {
        var oled = oled
        let legacyPath = oled["localAssetPath"] as? String
        let legacyFPS = (oled["framesPerSecond"] as? Int) ?? 12
        let stored = (oled["taskGIFAssets"] as? [[String: Any]]) ?? []

        var byState: [Int: [String: Any]] = [:]
        for asset in stored {
            guard let state = asset["state"] as? Int else { continue }
            byState[state] = asset
        }
        // done 缺省时按旧语义种子顶层默认动画路径（done 兼任默认动画）。
        if byState[3] == nil, legacyPath != nil {
            byState[3] = ["state": 3, "localAssetPath": legacyPath as Any, "framesPerSecond": legacyFPS]
        }
        // idle 回退 working 图（Rhino 语义），保证 3 态旧草稿迁入 4 态后待机不空屏。
        if byState[0] == nil, let working = byState[1] {
            var idle = working
            idle["state"] = 0
            byState[0] = idle
        }
        let setAAssets = [0, 1, 2, 3].map { state -> [String: Any] in
            byState[state] ?? ["state": state, "framesPerSecond": legacyFPS]
        }

        oled.removeValue(forKey: "taskGIFAssets")
        oled["taskGIFSets"] = [
            ["assets": setAAssets],
            ["assets": emptyAssets()],
        ]
        oled["activeGIFSet"] = 0
        oled["taskGIFSchemaVersion"] = taskGIFSchemaVersionLegacy
        return oled
    }

    private static func emptyAssets() -> [[String: Any]] {
        [0, 1, 2, 3].map { ["state": $0, "framesPerSecond": 12] }
    }

    /// 套图相等判定与顺序无关（Rhino 的归一化保证按 state 排序，这里更宽松一点）。
    private static func assetsEqualIgnoringOrder(_ a: [[String: Any]], _ b: [[String: Any]]) -> Bool {
        guard a.count == b.count else { return false }
        func key(_ asset: [String: Any]) -> Int { (asset["state"] as? Int) ?? -1 }
        let sa = a.sorted { key($0) < key($1) }
        let sb = b.sorted { key($0) < key($1) }
        return NSDictionary(dictionary: ["v": sa]).isEqual(to: ["v": sb])
    }
}
