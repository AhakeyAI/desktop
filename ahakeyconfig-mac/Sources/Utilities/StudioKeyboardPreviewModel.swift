import AhaKeyConfigShared
import Combine
import Foundation

@MainActor
final class StudioKeyboardPreviewModel: ObservableObject {
    @Published private(set) var state = StudioKeyboardPreviewState()
    private var transitionTask: Task<Void, Never>?

    func initialize(mode: Int) { state = .init(mode: mode); transitionTask?.cancel() }

    func send(_ action: StudioKeyboardPreviewState.Action) {
        var next = state
        let scheduled = next.send(action)
        guard next != state else { return }
        transitionTask?.cancel()
        state = next
        guard let scheduled else { transitionTask = nil; return }
        transitionTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(scheduled.milliseconds)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.send(.advance(revision: scheduled.revision))
        }
    }

    func cancel() { transitionTask?.cancel(); transitionTask = nil }

    var title: String {
        switch state.scene {
        case .artwork: return NSLocalizedString("当前模式画面", comment: "")
        case .daily: return NSLocalizedString("日常设备信息", comment: "")
        case .boot: return NSLocalizedString("开机动画", comment: "")
        case .reconnecting: return NSLocalizedString("连接中", comment: "")
        case .system: return NSLocalizedString("选择电脑系统", comment: "")
        case .shuttingDown: return NSLocalizedString("关机动画", comment: "")
        case .off: return NSLocalizedString("已关机", comment: "")
        }
    }
}
