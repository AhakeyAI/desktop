import Foundation

/// OLED 默认动画绑定修复计划（纯函数，便于单测）。
///
/// legacy 固件没有 idle 任务槽：切换 Mode 后显示 0x82 写入的默认动画绑定，
/// 因此旧协议需要把 done 任务图的帧区间额外绑定到 0x82。
/// current 固件有独立 idle 槽，禁止用 0x82 覆盖普通每模式动画。
public enum AhaKeyOLEDSyncPlan {
    /// 一段 flash 帧区间绑定：起始槽、帧数、帧间隔（毫秒）。
    public struct Binding: Equatable, Sendable {
        public let startIndex: Int
        public let frameCount: Int
        public let frameIntervalMs: Int

        public init(startIndex: Int, frameCount: Int, frameIntervalMs: Int) {
            self.startIndex = startIndex
            self.frameCount = frameCount
            self.frameIntervalMs = frameIntervalMs
        }
    }

    /// 判断是否需要把 done 槽位重新绑定为该 Mode 的默认动画（0x82）。
    /// - Parameters:
    ///   - doneAssetPath: 草稿中 done 状态的本地图路径；为 nil 表示用户未设置，不绑定。
    ///   - deviceDone: 设备上 done 槽位的当前绑定（legacy 0x94 查询结果或刚上传完成后的值）。
    ///   - deviceDefault: 设备默认动画绑定（0x83 查询结果）；查询不到时传 nil，
    ///     此时只要 done 槽有帧就保守地重新绑定一次（0x82 是幂等绑定，不写 flash 数据区）。
    /// - Returns: 需要绑定时返回目标绑定（取 done 槽位的区间），否则返回 nil。
    public static func defaultBindingRepair(
        doneAssetPath: String?,
        deviceDone: Binding?,
        deviceDefault: Binding?
    ) -> Binding? {
        guard doneAssetPath != nil,
              let done = deviceDone,
              done.frameCount > 0
        else { return nil }
        guard let current = deviceDefault else { return done }
        return current == done ? nil : done
    }

    /// M2b1 协议分叉版本：0x82 默认绑定修复只保留 legacy 语义。
    ///
    /// - legacy 固件：没有 idle 任务槽，模式切换后的默认动画只能由 0x82 绑定
    ///   `key_bund.pic[mode]`，因此维持「done→0x82」修复（与主线修复前行为逐字节一致）。
    /// - current 固件：默认动画由 idle 任务槽（0x95 set/state=idle）覆盖出厂默认，
    ///   **不再发 0x82**——避免任务图写入意外替换普通每模式动画绑定。
    /// - negotiating / restrictedUnknown：不允许任务图配置，同样不发 0x82。
    public static func defaultBindingRepair(
        protocolMode: AhaKeyProtocolMode,
        doneAssetPath: String?,
        deviceDone: Binding?,
        deviceDefault: Binding?
    ) -> Binding? {
        guard protocolMode == .legacy else { return nil }
        return defaultBindingRepair(
            doneAssetPath: doneAssetPath,
            deviceDone: deviceDone,
            deviceDefault: deviceDefault
        )
    }
}
