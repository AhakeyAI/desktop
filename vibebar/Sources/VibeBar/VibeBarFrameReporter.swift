import AppKit
import SwiftUI

/// Reports the rendered SwiftUI content in global AppKit coordinates. The oversized
/// transparent DynamicNotch panel frame is deliberately never used as a hit target.
struct VibeBarFrameReporter: NSViewRepresentable {
    let contentFrame: CGRect
    let report: (CGRect, NSScreen) -> Void

    func makeNSView(context: Context) -> ReportingView { ReportingView(contentFrame: contentFrame, report: report) }
    func updateNSView(_ view: ReportingView, context: Context) {
        view.contentFrame = contentFrame
        view.report = report
        view.scheduleReport()
    }

    @MainActor
    final class ReportingView: NSView {
        var contentFrame: CGRect
        var report: (CGRect, NSScreen) -> Void
        private var lastFrame: CGRect?
        private var lastScreenFrame: CGRect?
        private var reportPending = false

        init(contentFrame: CGRect, report: @escaping (CGRect, NSScreen) -> Void) {
            self.contentFrame = contentFrame
            self.report = report
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleReport() }
        override func layout() { super.layout(); scheduleReport() }

        func scheduleReport() {
            guard !reportPending else { return }
            reportPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportPending = false
                guard let window = self.window, let screen = window.screen,
                      self.bounds.width > 0, self.bounds.height > 0 else { return }
                guard let root = window.contentView else { return }
                var rect = self.contentFrame
                if !root.isFlipped { rect.origin.y = root.bounds.height - rect.maxY }
                let frame = window.convertToScreen(root.convert(rect, to: nil))
                guard frame != self.lastFrame || screen.frame != self.lastScreenFrame else { return }
                self.lastFrame = frame
                self.lastScreenFrame = screen.frame
                self.report(frame, screen)
            }
        }
    }
}
