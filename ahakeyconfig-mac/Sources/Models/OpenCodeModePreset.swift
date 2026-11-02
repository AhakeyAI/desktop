import Foundation

/// opencode 的 **LCD 显示预设**。
///
/// AhaKey 键盘只有 4 个物理 Mode（`AhaKeyModeSlot.mode0…mode3`），mode3 出厂是「自定义」。
/// 所以「支援 opencode」不是凭空多出第五个 Mode，而是把**使用者目前选中的那个 Mode**
/// 一键套成 opencode 的显示预设：模式名称、内置 `opencode.gif`、LCD 状态行、12 FPS。
///
/// 键位刻意不动：
/// `AhaKeyModeDraft.default(for: .mode3)` 已经是 Enter（允许）/ Esc（拒绝）/ Backspace（收回），
/// 正好对上 opencode TUI 的权限提示；但每个人的终端习惯不同，交给使用者在编辑器里自己微调更合适。
///
/// 本类型只负责「算出预设值」，不碰 UI、不碰 BLE —— 写入键盘仍走既有的「写入键盘」流程。
enum OpenCodeModePreset {
    /// bundle 内 `DefaultOLED/` 下的文件名（不含扩展名）。
    static let assetName = "opencode"

    /// 模式显示名称（写进 `AhaKeyModeNameStore`）。
    static let displayName = "opencode"

    /// 与随附的 `opencode.gif` 一致：24 帧、一圈 2 秒。
    static let framesPerSecond = 12

    static var statusLine: String {
        NSLocalizedString("opencode · 权限提示 Enter 允许 / Esc 拒绝。", comment: "")
    }

    /// bundle 里 `opencode.gif` 的绝对路径；安装包没带上时返回 nil。
    static var bundledAssetPath: String? {
        DefaultOLEDAssets.bundledAssetPath(forName: assetName)
    }

    static var isAssetAvailable: Bool {
        bundledAssetPath != nil
    }

    /// 产出套用后的 LCD 草稿；`needsDeviceUpload` 置 true，确保下一次「写入键盘」会把它推上设备。
    ///
    /// 回传 nil 而不是退化成「没有图」的空草稿：资源缺失是安装包问题，
    /// 静默写一个空路径会让使用者以为套用成功、实际上键盘上什么都没有。
    static func oledDraft() -> AhaKeyOLEDDraft? {
        guard let path = bundledAssetPath else { return nil }
        return AhaKeyOLEDDraft(
            localAssetPath: path,
            statusLine: statusLine,
            framesPerSecond: framesPerSecond,
            needsDeviceUpload: true
        )
    }

    /// 燈條語意（IDE 狀態 → 效果）。刻意与 Claude/Cursor 的默认不同：
    /// - 执行中 `breathing`（整条呼吸，蓝）
    /// - 工具完成 `singleMove`（单点蓝色来回流水：柔和、不闪烁，与「整条呼吸」明显不同）
    /// - 任务完成 `successSweep`（绿扫）、权限 `approvalWait`（琥珀呼吸）、停止 `middleLight`
    ///
    /// 实机踩过的坑：`comet` 是红色（会被误读成错误）、`typingRipple` 闪烁刺眼、
    /// `blueThinking` 与 `breathing` 视觉重复 —— 这三者都不要再拿来当「工具完成」。
    static let lightBarMappings: [AhaKeyLightStateDraft] = [
        AhaKeyLightStateDraft(state: .notification, effect: .pulseCenter),
        AhaKeyLightStateDraft(state: .permissionRequest, effect: .approvalWait),
        AhaKeyLightStateDraft(state: .postToolUse, effect: .singleMove),
        AhaKeyLightStateDraft(state: .preToolUse, effect: .breathing),
        AhaKeyLightStateDraft(state: .sessionStart, effect: .rainbowWave),
        AhaKeyLightStateDraft(state: .stop, effect: .middleLight),
        AhaKeyLightStateDraft(state: .taskCompleted, effect: .successSweep),
        AhaKeyLightStateDraft(state: .userPromptSubmit, effect: .breathing),
        AhaKeyLightStateDraft(state: .sessionEnd, effect: .off),
    ]

    /// 還原成該 Mode 的出廠（custom）預設：清掉 LCD 圖、燈效映射回到 default。
    /// 名稱由呼叫方（View）負責清掉 custom name，讓分頁標題回到 `AhaKeyModeSlot.defaultName`。
    static func restoreCustomDraft(_ draft: inout AhaKeyModeDraft) {
        draft.oled = .default(for: draft.mode)
        draft.oled.needsDeviceUpload = true
        draft.lightBar = .default(for: draft.mode)
    }

    /// 就地套用到一份 mode 草稿（LCD + 燈條映射）。
    @discardableResult
    static func apply(to draft: inout AhaKeyModeDraft) -> Bool {
        guard let oled = oledDraft() else { return false }
        draft.oled = oled
        draft.lightBar = AhaKeyLightBarDraft(
            stateMappings: lightBarMappings,
            brightness: draft.lightBar.brightness
        )
        return true
    }
}
