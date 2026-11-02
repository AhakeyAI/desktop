import Foundation

/// Presentation follows the physical mode; it never narrows the authority of
/// the shared lever or treats a requested permission change as acknowledged.
enum StudioLeverPresentation {
    struct Notice: Equatable {
        let title: String
        let message: String
        let offersCodexManagement: Bool
    }

    static func notice(mode: Int?, automatic: Bool, codexManaged: Bool,
                       backgroundConnected: Bool, hooksInstalled: Bool) -> Notice {
        let slot = mode.flatMap(AhaKeyModeSlot.init(rawValue:))
        let name = slot?.defaultName ?? NSLocalizedString("拨杆", comment: "")
        let position = NSLocalizedString(automatic ? "自动档" : "手动档", comment: "")
        let title = name + " · " + position
        guard backgroundConnected else {
            return Notice(title: title, message: NSLocalizedString("后台未连接，权限尚未同步。", comment: ""), offersCodexManagement: false)
        }
        let message: String
        switch slot {
        case .mode0?, .mode1?:
            message = NSLocalizedString(automatic
                ? (hooksInstalled ? "审批请求由后台自动处理。" : "尚未配置自动批准，请在拨杆设置中完成配置。")
                : "已停止代批，沿用应用原有审批。", comment: "")
        case .mode2?:
            message = NSLocalizedString(codexManaged
                ? (automatic ? "已请求完全访问，下一轮生效。" : "已请求批准模式，下一轮生效。")
                : "未接管，沿用 Codex 当前权限。", comment: "")
        case .mode3?:
            message = NSLocalizedString("已授权桌面会话跟随拨杆；CLI 仅影响新会话。", comment: "")
        case nil:
            message = NSLocalizedString("拨杆已切换；请查看当前模式的权限状态。", comment: "")
        }
        return Notice(title: title, message: message,
                      offersCodexManagement: slot == .mode2 && automatic && !codexManaged && hooksInstalled)
    }
}
