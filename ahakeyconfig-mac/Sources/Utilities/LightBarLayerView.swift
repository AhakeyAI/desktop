import AppKit

/// The light-strip clock updates backing layers without invalidating SwiftUI
/// layout for the surrounding keyboard or inspector.
@MainActor
final class LightBarLayerView: NSView {
    private let bars = (0..<10).map { _ in CALayer() }
    private var colors: ((TimeInterval) -> [CGColor])?
    private var requestedFPS: Double?
    private var playbackFPS: Double?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var dismantled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        bars.forEach { layer?.addSublayer($0) }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(framesPerSecond: Double?, colors: @escaping (TimeInterval) -> [CGColor]) {
        guard !dismantled else { return }
        self.colors = colors
        requestedFPS = framesPerSecond.flatMap { $0.isFinite && $0 > 0 ? min($0, 60) : nil }
        render(at: requestedFPS == nil ? 0 : Date().timeIntervalSince1970)
        refreshPlayback()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = min(12, bounds.height / 2)
        let padding = bounds.width * 0.04
        let spacing = bounds.width * 0.026
        let width = max(0, bounds.width - padding * 2 - spacing * 9) / 10
        let height = bounds.height * (0.26 / 0.48)
        for (index, bar) in bars.enumerated() {
            bar.frame = CGRect(x: padding + CGFloat(index) * (width + spacing),
                               y: (bounds.height - height) / 2, width: width, height: height)
            bar.cornerRadius = height / 2
        }
        CATransaction.commit()
    }

    func render(at time: TimeInterval) {
        guard !dismantled, let colors else { return }
        let values = colors(time)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.isHidden = index >= values.count
            if index < values.count { bar.backgroundColor = values[index] }
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard !dismantled else { return }
        if let window {
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if note.name == NSWindow.willCloseNotification { self?.stopPlayback() }
                        else { self?.refreshPlayback() }
                    }
                })
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                         NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshPlayback() }
                })
            }
        }
        refreshPlayback()
    }

    private func refreshPlayback() {
        guard !dismantled, let fps = requestedFPS, let window,
              window.isVisible, !window.isMiniaturized, NSApp.isActive else {
            stopPlayback()
            return
        }
        guard timer == nil || playbackFPS != fps else { return }
        stopPlayback()
        playbackFPS = fps
        let clock = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(at: Date().timeIntervalSince1970) }
        }
        clock.tolerance = 0.05 / fps
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
    }

    private func stopPlayback() {
        timer?.invalidate()
        timer = nil
        playbackFPS = nil
    }

    func dismantle() {
        dismantled = true
        stopPlayback()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        colors = nil
    }

    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
