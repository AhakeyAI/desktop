import Foundation

/// OLED 默认动画绑定修复计划（纯函数，便于单测）。
///
/// 固件语义（CH582 固件 `main.c` / `command_solve.c`）：
/// 切换到某个 Mode 且没有 hook 状态驱动时，`ai_oled_state == AI_OLED_IDLE`，
/// 键盘显示的是「默认动画绑定」——0x82 写入的 `key_bund.pic[mode]`（固件会把它
/// 镜像到各套图的 IDLE 任务槽）。任务图上传（0x95）只绑定 working/waiting/done
/// 状态槽，不会触碰默认动画绑定。
/// 产品设计是 done 状态图同时作为模式切换后的默认动画，因此写入流程必须保证
/// 设备的默认动画绑定（0x83 可读）与 done 槽位（0x96 可读）一致，否则用户
/// 自定义的 done 图上传成功后，模式切换画面仍显示旧默认图。
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
    ///   - deviceDone: 设备上 done 槽位的当前绑定（0x96 查询结果或刚上传完成后的值）。
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
}
