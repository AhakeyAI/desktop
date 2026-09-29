import Foundation

/// 由 `DeviceStateReducer.apply` 前后的两份核心快照 diff 出一句简短的状态变化摘要，
/// 供 manager 记默认永久级日志（例：`拨杆 0→1, 模式 1→2`，一条即可，不逐字段多条）。
/// 连接状态与设备身份不在此摘要内——它们由连接生命周期日志（已连接/已断开）覆盖。
public enum CoreSnapshotChangeSummary {
    /// 无值得记录的变化时返回 nil。
    public static func summarize(from old: CoreDeviceSnapshot, to new: CoreDeviceSnapshot) -> String? {
        var changes: [String] = []
        if old.batteryLevel != new.batteryLevel {
            changes.append("电量 \(old.batteryLevel)→\(new.batteryLevel)")
        }
        if old.firmwareMainVersion != new.firmwareMainVersion || old.firmwareSubVersion != new.firmwareSubVersion {
            changes.append("固件 \(old.firmwareMainVersion).\(old.firmwareSubVersion)→\(new.firmwareMainVersion).\(new.firmwareSubVersion)")
        }
        if old.workMode != new.workMode {
            changes.append("模式 \(old.workMode)→\(new.workMode)")
        }
        if old.lightMode != new.lightMode {
            changes.append("灯效 \(old.lightMode)→\(new.lightMode)")
        }
        if old.switchState != new.switchState {
            changes.append("拨杆 \(old.switchState)→\(new.switchState)")
        }
        if old.brightness != new.brightness {
            changes.append("亮度 \(old.brightness)→\(new.brightness)")
        }
        if old.activeTaskPictureSets != new.activeTaskPictureSets {
            changes.append("任务套图 \(format(old.activeTaskPictureSets))→\(format(new.activeTaskPictureSets))")
        }
        return changes.isEmpty ? nil : changes.joined(separator: ", ")
    }

    private static func format(_ sets: [Int: Int]) -> String {
        guard !sets.isEmpty else { return "—" }
        return sets.sorted { $0.key < $1.key }.map { "mode\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}
