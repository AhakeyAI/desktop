import Foundation
import AhaKeyConfigShared

/// Presentation follows the physical mode; it never narrows the authority of
/// the shared lever or treats a requested permission change as acknowledged.
enum StudioLeverPresentation {
    struct Notice: Equatable {
        let title: String
        let subtitle: String
        let message: String
        let offersCodexManagement: Bool
    }

    static func notice(position: Int, action: LeverAssignedAction, bytes: Data? = nil, mode: Int?,
                       codexManaged: Bool, backgroundConnected: Bool, hooksInstalled: Bool) -> Notice {
        let title = position == 0 ? NSLocalizedString("拨杆在上", comment: "") : NSLocalizedString("拨杆在下", comment: "")
        let subtitle = action.title
        if action == .disabled {
            return Notice(title: title, subtitle: subtitle, message: NSLocalizedString("此档位没有绑定动作。", comment: ""),
                          offersCodexManagement: false)
        }
        if action == .shortcut || action == .macro {
            let opcode: UInt8 = action == .shortcut ? 0x73 : 0x74
            let message: String
            if let bytes, bytes.first == opcode, SideSwitchBindingConfiguration.validAction(bytes) {
                if action == .macro {
                    let steps = Array(bytes.dropFirst(2))
                    message = stride(from: 0, to: steps.count, by: 2).map { index in
                        let step = MacroStep(action: MacroAction(rawValue: steps[index]) ?? .noOp, param: steps[index + 1])
                        switch step.action {
                        case .downKey, .upKey: return step.action.title + " " + HIDUsage.name(for: step.param)
                        case .delay: return String(format: NSLocalizedString("延时 %d ms", comment: ""), Int(step.param) * 3)
                        case .noOp, .upAllKeys: return step.action.title
                        }
                    }.joined(separator: " → ")
                } else {
                    message = StudioKeyWriteProposal.actionSummary(.init(mode: 0, keyIndex: 0, actionType: opcode,
                        action: Data(bytes.dropFirst(2)), description: Data()))
                }
            } else { message = NSLocalizedString("未能读取此绑定的动作详情。", comment: "") }
            return Notice(title: title, subtitle: subtitle, message: message, offersCodexManagement: false)
        }
        let automatic = action == .automatic
        let slot = mode.flatMap(AhaKeyModeSlot.init(rawValue:))
        guard backgroundConnected else {
            return Notice(title: title, subtitle: subtitle, message: NSLocalizedString("后台未连接，权限尚未同步。", comment: ""), offersCodexManagement: false)
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
        return Notice(title: title, subtitle: subtitle, message: message,
                      offersCodexManagement: slot == .mode2 && automatic && !codexManaged && hooksInstalled)
    }
}
