import Foundation
import AhaKeyConfigShared

/// A choice affects only future setup offers. It never changes Hook grants or
/// the permissions of a running Codex session.
@MainActor
final class CodexApprovalSetupModel {
    enum Choice: String { case undecided, keepCurrent, requestedApproval }
    enum Result { case keptCurrent, configured, failed }
    private let readChoice: () -> Choice
    private let saveChoice: (Choice) -> Void
    private let configure: () -> Bool
    private(set) var isPresenting = false

    init(readChoice: @escaping () -> Choice, saveChoice: @escaping (Choice) -> Void,
         configure: @escaping () -> Bool) {
        self.readChoice = readChoice; self.saveChoice = saveChoice; self.configure = configure
    }

    func offer(force: Bool = false) -> Bool {
        guard !isPresenting, force || readChoice() == .undecided else { return false }
        isPresenting = true
        return true
    }

    func resolve(useRequestedApproval: Bool) -> Result {
        guard isPresenting else { return .failed }
        isPresenting = false
        guard useRequestedApproval else {
            saveChoice(.keepCurrent)
            return .keptCurrent
        }
        guard configure() else { return .failed }
        saveChoice(.requestedApproval)
        return .configured
    }
}

@MainActor
final class CodexApprovalSetupController {
    static let shared = CodexApprovalSetupController()
    private let model = CodexApprovalSetupModel(
        readChoice: { CodexApprovalSetupModel.Choice(rawValue: UserDefaults.standard.string(forKey: "codexApprovalSetupChoice") ?? "") ?? .undecided },
        saveChoice: { UserDefaults.standard.set($0.rawValue, forKey: "codexApprovalSetupChoice") },
        configure: {
            switch CodexConfigLeverSync.configureRequestedApproval() {
            case .alreadyDesired, .replaced, .inserted: return true
            default: return false
            }
        })

    func requestOffer(force: Bool = false) {
        guard model.offer(force: force) else { return }
        VoiceStatusHUDController.shared.offerCodexApproval { [weak self] accept in
            guard let self else { return }
            switch self.model.resolve(useRequestedApproval: accept) {
            case .keptCurrent: break
            case .configured:
                VoiceStatusHUDController.shared.show(.init(kind: .success,
                    title: NSLocalizedString("已设置默认请求批准", comment: ""),
                    subtitle: NSLocalizedString("当前会话请在 Codex 切换权限或新建会话", comment: "")), autoHideAfter: 6)
            case .failed:
                VoiceStatusHUDController.shared.show(.init(kind: .warning,
                    title: NSLocalizedString("未能修改 Codex 默认权限", comment: ""),
                    subtitle: NSLocalizedString("原有权限保留，可在 Codex 中手动设置", comment: "")), autoHideAfter: 6)
            }
        }
    }
}
