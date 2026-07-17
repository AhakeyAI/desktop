import Foundation

/// 保留旧名称的兼容性入口，内部已迁移到 `KimiPermissionModeController`。
///
/// 旧逻辑写 `~/.kimi/config.toml` 的 `default_yolo` 并提示 `/reload`；新逻辑写
/// `~/.kimi-code/config.toml` 的 `default_permission_mode`，作为未来新 Kimi 会话的
/// 默认权限模式兜底。
enum KimiConfigLeverSync {
    static func apply(switchStateAuto: Bool) {
        let switchState: Int? = switchStateAuto ? 0 : 1
        _ = KimiPermissionModeController.applyConfigLayer(forSwitchState: switchState)
    }

    /// 供 `permission-request.log`：`kimiLeverDebug`。
    static func diagnosticSnapshotForLog() -> [String: Any] {
        KimiConfigDiagnostic.snapshotForLog()
    }
}
