import Foundation
import AhaKeyConfigShared

/// New consent to manage original desktop sessions, independent of the retired
/// choice which only authorized changing the default config file.
@MainActor
final class CodexApprovalSetupModel {
    enum Choice: String { case undecided, keepCurrent, managedSessions }
    enum Result { case keptCurrent, configured, failed }
    private let readChoice: () -> Choice
    private let saveChoice: (Choice) -> Void
    private let configure: () -> Bool
    private let revoke: () -> Bool
    private(set) var isPresenting = false
    static func persistedChoice(defaults: UserDefaults, managementEnabled: Bool) -> Choice {
        if managementEnabled { return .managedSessions }
        return Choice(rawValue: defaults.string(forKey: "codexDesktopLeverChoiceV1") ?? "") == .keepCurrent ? .keepCurrent : .undecided
    }

    init(readChoice: @escaping () -> Choice, saveChoice: @escaping (Choice) -> Void,
         configure: @escaping () -> Bool, revoke: @escaping () -> Bool = { true }) {
        self.readChoice = readChoice; self.saveChoice = saveChoice; self.configure = configure
        self.revoke = revoke
    }

    func offer(force: Bool = false) -> Bool {
        guard !isPresenting, force || readChoice() == .undecided else { return false }
        isPresenting = true
        return true
    }

    func resolve(manageSessions: Bool) -> Result {
        guard isPresenting else { return .failed }
        isPresenting = false
        guard manageSessions else {
            guard revoke() else { return .failed }
            saveChoice(.keepCurrent)
            return .keptCurrent
        }
        guard configure() else { return .failed }
        saveChoice(.managedSessions)
        return .configured
    }
}

@MainActor
final class CodexApprovalSetupController {
    static let shared = CodexApprovalSetupController(model: CodexApprovalSetupModel(
        readChoice: {
            CodexApprovalSetupModel.persistedChoice(defaults: .standard,
                managementEnabled: (try? CodexDesktopLeverState().snapshot().managementEnabled) == true)
        },
        saveChoice: { UserDefaults.standard.set($0.rawValue, forKey: "codexDesktopLeverChoiceV1") },
        configure: {
            do { try CodexDesktopLeverState().setManagementEnabled(true); return true } catch { return false }
        }, revoke: {
            do { try CodexDesktopLeverState().setManagementEnabled(false); return true } catch { return false }
        }), hud: .shared)
    private let model: CodexApprovalSetupModel
    private let hud: VoiceStatusHUDController

    init(model: CodexApprovalSetupModel, hud: VoiceStatusHUDController) {
        self.model = model; self.hud = hud
    }

    func requestOffer(force: Bool = false) {
        if model.isPresenting {
            if force { hud.refreshPendingOffer() }
            return
        }
        guard model.offer(force: force) else { return }
        hud.offerCodexApproval { [weak self] accept in
            guard let self else { return }
            switch self.model.resolve(manageSessions: accept) {
            case .keptCurrent:
                self.hud.show(.init(kind: .success, title: NSLocalizedString("未启用权限接管", comment: ""),
                    subtitle: NSLocalizedString("已有接管由后台恢复，继续 Codex 原有审批流程", comment: "")), autoHideAfter: 6)
            case .configured:
                self.hud.show(.init(kind: .success,
                    title: NSLocalizedString("已允许拨杆管理权限", comment: ""),
                    subtitle: NSLocalizedString("等待后台同步；当前轮权限不变", comment: "")), autoHideAfter: 6)
            case .failed:
                self.hud.show(.init(kind: .warning,
                    title: NSLocalizedString("未能更新权限管理选择", comment: ""),
                    subtitle: NSLocalizedString("请稍后重试，未确认已同步", comment: "")), autoHideAfter: 6)
            }
        }
    }
}
