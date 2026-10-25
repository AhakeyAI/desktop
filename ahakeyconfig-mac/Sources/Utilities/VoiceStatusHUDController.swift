import AppKit
import SwiftUI

@MainActor
final class VoiceStatusHUDController {
    static let shared = VoiceStatusHUDController()

    private var panel: NSPanel?
    private let makePanel: @MainActor () -> NSPanel
    private var hostingView: NSHostingView<VoiceStatusHUDView>?
    private var hideWorkItem: DispatchWorkItem?
    private var pendingOffer: ((Bool) -> Void)?
    private var voiceVisible = false
    private var hideGeneration = UUID()

    /// Voice always takes priority. Offers wait until recording/processing ends.
    func offerCodexApproval(_ completion: @escaping (Bool) -> Void) {
        if pendingOffer == nil { pendingOffer = completion }
        refreshPendingOffer()
    }

    func refreshPendingOffer() {
        if !voiceVisible { displayOffer() }
    }

    private func displayOffer() {
        guard pendingOffer != nil, !voiceVisible else { return }
        hideWorkItem?.cancel()
        let panel = ensurePanel()
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = InteractiveHUDHostingView(rootView: CodexApprovalOfferView { [weak self] accept in
            guard let self else { return }
            let action = self.pendingOffer
            self.pendingOffer = nil
            self.panel?.orderOut(nil)
            action?(accept)
        })
        panel.setContentSize(NSSize(width: 390, height: 150))
        position(panel)
        panel.orderFrontRegardless()
    }

    init(makePanel: @escaping @MainActor () -> NSPanel = {
        NonActivatingVoiceHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 58),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }) { self.makePanel = makePanel }

    /// Build the hidden UI at app startup, without opening the microphone or
    /// stealing focus on the user's first physical press.
    func prepare() {
        guard hostingView == nil else { return }
        let host = NSHostingView(rootView: VoiceStatusHUDView(state: .done))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 58)
        hostingView = host
        ensurePanel().contentView = host
    }

    func show(_ state: VoiceStatusHUDState, autoHideAfter delay: TimeInterval? = nil) {
        hideWorkItem?.cancel()
        hideGeneration = UUID()
        voiceVisible = true
        prepare()
        hostingView?.rootView = VoiceStatusHUDView(state: state)

        let panel = ensurePanel()
        panel.contentView = hostingView
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.setContentSize(NSSize(width: 360, height: 58))
        position(panel)
        panel.orderFrontRegardless()

        if let delay {
            let generation = hideGeneration
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, self.hideGeneration == generation else { return }
                    self.hide()
                }
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hideGeneration = UUID()
        voiceVisible = false
        panel?.orderOut(nil)
        displayOffer()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = makePanel()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.minY + 44
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class NonActivatingVoiceHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The prompt must accept a click while another app remains active. It never
/// becomes key, so choosing an option does not move the user's text focus.
private final class InteractiveHUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct VoiceStatusHUDState: Equatable {
    enum Kind {
        case recording
        case processing
        case success
        case warning
    }

    let kind: Kind
    let title: String
    let subtitle: String

    static let recording = VoiceStatusHUDState(kind: .recording, title: NSLocalizedString("录音中", comment: ""), subtitle: NSLocalizedString("再次按语音键结束", comment: ""))
    static let starting = VoiceStatusHUDState(kind: .processing, title: NSLocalizedString("正在启动麦克风", comment: ""), subtitle: NSLocalizedString("就绪后说话，再按可取消", comment: ""))
    static let recognizing = VoiceStatusHUDState(kind: .processing, title: NSLocalizedString("本地识别中", comment: ""), subtitle: NSLocalizedString("正在整理语音文本", comment: ""))
    static let ahaType = VoiceStatusHUDState(kind: .processing, title: NSLocalizedString("AhaType 整理中", comment: ""), subtitle: NSLocalizedString("云端正在优化文本", comment: ""))
    static let pasting = VoiceStatusHUDState(kind: .processing, title: NSLocalizedString("准备粘贴", comment: ""), subtitle: NSLocalizedString("正在写入当前光标", comment: ""))
    static let done = VoiceStatusHUDState(kind: .success, title: NSLocalizedString("已写入", comment: ""), subtitle: NSLocalizedString("语音文本已完成", comment: ""))
    static let rawWritten = VoiceStatusHUDState(kind: .warning, title: NSLocalizedString("已写入原始文字", comment: ""), subtitle: NSLocalizedString("AhaType 未整理，原因见 AhaType 状态", comment: ""))
    static let empty = VoiceStatusHUDState(kind: .warning, title: NSLocalizedString("未识别到内容", comment: ""), subtitle: NSLocalizedString("请靠近麦克风重试", comment: ""))
    static let failed = VoiceStatusHUDState(kind: .warning, title: NSLocalizedString("写入失败", comment: ""), subtitle: NSLocalizedString("请检查输入权限", comment: ""))
}

private struct VoiceStatusHUDView: View {
    let state: VoiceStatusHUDState

    var body: some View {
        HStack(spacing: 12) {
            indicator
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(state.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 360, height: 58)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        switch state.kind {
        case .recording:
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.16))
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
            }
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.green)
        case .warning:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.orange)
        }
    }
}


private struct CodexApprovalOfferView: View {
    let resolve: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("允许拨杆管理 Codex 权限？", systemImage: "checkmark.shield")
                .font(.system(size: 14, weight: .semibold))
            Text("管理已识别的本机桌面会话：自动档为完全访问，手动档为请求批准，同一会话下一轮生效。暂停或断连时恢复接管前权限。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("暂不接管") { resolve(false) }
                Spacer()
                Button("允许拨杆管理") { resolve(true) }.buttonStyle(.borderedProminent)
            }.controlSize(.small)
        }
        .padding(16).frame(width: 390, height: 150)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .windowBackgroundColor)))
    }
}
