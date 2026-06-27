import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
public final class VibeBarController {
    public static let shared = VibeBarController()

    private var notch: (any DynamicNotchControllable)?
    private var pendingCompactTask: Task<Void, Never>?
    private var pointerTimer: Timer?
    private var isHoveringExpanded = false
    private var isExpanded = false
    private weak var state: VibeBarState?

    private init() {}

    /// 在主 app 启动后调用一次。多次调用是空操作。
    public func start(state: VibeBarState) {
        guard notch == nil else { return }
        self.state = state

        let notch = DynamicNotch(
            hoverBehavior: [.increaseShadow],
            style: .notch
        ) { [weak self] in
            VibeBarExpandedMenu(
                state: state,
                onAppear: { self?.expandedMenuAppeared() },
                onHoverChanged: { self?.expandedHoverChanged($0) },
                onCompact: { self?.compactNow() },
                onOpenMain: { state.onOpenMainWindow?() }
            )
        } compactLeading: { [weak self] in
            VibeBarCompactKeyboardItem(state: state) { hovering in
                self?.compactHoverChanged(hovering)
            }
        } compactTrailing: { [weak self] in
            VibeBarCompactLeverItem(state: state) { hovering in
                self?.compactHoverChanged(hovering)
            }
        }

        self.notch = notch
        startPointerTracking()
        compactNow()
    }

    public func stop() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        pendingCompactTask?.cancel()
        pendingCompactTask = nil
        notch = nil
        state = nil
    }

    // MARK: - Notch state machine

    private func compactNow() {
        pendingCompactTask?.cancel()
        isExpanded = false
        isHoveringExpanded = false
        Task { await notch?.compact(on: targetScreen) }
    }

    private func expandNow() {
        pendingCompactTask?.cancel()
        isExpanded = true
        Task { await notch?.expand(on: targetScreen) }
    }

    private func compactHoverChanged(_ hovering: Bool) {
        if hovering { expandNow() }
    }

    private func expandedMenuAppeared() {
        pendingCompactTask?.cancel()
        isExpanded = true
    }

    private func expandedHoverChanged(_ hovering: Bool) {
        isHoveringExpanded = hovering
        if hovering {
            pendingCompactTask?.cancel()
        } else {
            scheduleCompactIfIdle()
        }
    }

    private func scheduleCompactIfIdle() {
        pendingCompactTask?.cancel()
        pendingCompactTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.compactIfIdle()
        }
    }

    private func compactIfIdle() {
        guard isExpanded, !isHoveringExpanded else { return }
        compactNow()
    }

    private func startPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expandIfPointerIsInTopHotZone() }
        }
        RunLoop.main.add(pointerTimer!, forMode: .common)
    }

    private func expandIfPointerIsInTopHotZone() {
        guard !isExpanded, topHotZone.contains(NSEvent.mouseLocation) else { return }
        expandNow()
    }

    private var topHotZone: CGRect {
        let screen = targetScreen
        let width: CGFloat = 440
        let height: CGFloat = 58
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private var targetScreen: NSScreen {
        NSScreen.main ?? NSScreen.screens.first!
    }
}
