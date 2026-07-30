import AppKit
import SwiftUI

@MainActor
final class VoiceStatusHUDController {
    static let shared = VoiceStatusHUDController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<VoiceStatusHUDView>?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func show(_ state: VoiceStatusHUDState, autoHideAfter delay: TimeInterval? = nil) {
        hideWorkItem?.cancel()
        let view = VoiceStatusHUDView(state: state)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 58)
            self.hostingView = hostingView
        }

        let panel = ensurePanel()
        if let hostingView, hostingView.superview == nil {
            panel.contentView = hostingView
        }
        position(panel)
        panel.orderFrontRegardless()

        if let delay {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.hide()
                }
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NonActivatingVoiceHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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

    static let recording = VoiceStatusHUDState(kind: .recording, title: "录音中", subtitle: "再次按语音键结束")
    static let recognizing = VoiceStatusHUDState(kind: .processing, title: "本地识别中", subtitle: "正在整理语音文本")
    static let ahaType = VoiceStatusHUDState(kind: .processing, title: "AhaType 整理中", subtitle: "云端正在优化文本")
    static let pasting = VoiceStatusHUDState(kind: .processing, title: "准备粘贴", subtitle: "正在写入当前光标")
    static let done = VoiceStatusHUDState(kind: .success, title: "已写入", subtitle: "语音文本已完成")
    static let empty = VoiceStatusHUDState(kind: .warning, title: "未识别到内容", subtitle: "请靠近麦克风重试")
    static let failed = VoiceStatusHUDState(kind: .warning, title: "写入失败", subtitle: "请检查输入权限")
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
        .frame(width: 260, height: 58)
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
