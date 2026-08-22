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
    private var presentationScreen: NSScreen?
    private var desiredPresentation: Presentation = .compact
    private var presentationTask: Task<Void, Never>?

    private enum Presentation: Equatable {
        case compact
        case expanded
    }

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
        presentationScreen = screenContainingPointer() ?? NSScreen.main ?? NSScreen.screens.first
        compactNow()
        startPointerTracking()
    }

    public func stop() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        pendingCompactTask?.cancel()
        pendingCompactTask = nil
        presentationTask?.cancel()
        presentationTask = nil
        notch = nil
        state = nil
        presentationScreen = nil
    }

    // MARK: - Notch state machine

    private func compactNow() {
        cancelPendingCompact()
        isExpanded = false
        isHoveringExpanded = false
        requestPresentation(.compact, on: presentationScreen ?? preferredScreen)
    }

    private func expandNow(on screen: NSScreen? = nil) {
        cancelPendingCompact()
        isExpanded = true
        requestPresentation(.expanded, on: screen ?? screenContainingPointer() ?? preferredScreen)
    }

    private func compactHoverChanged(_ hovering: Bool) {
        if hovering { expandNow(on: screenContainingPointer()) }
    }

    private func expandedMenuAppeared() {
        cancelPendingCompact()
        isExpanded = true
    }

    private func expandedHoverChanged(_ hovering: Bool) {
        isHoveringExpanded = hovering
        if hovering {
            cancelPendingCompact()
        } else {
            scheduleCompactIfIdle()
        }
    }

    private func scheduleCompactIfIdle() {
        guard pendingCompactTask == nil else { return }
        pendingCompactTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.pendingCompactTask = nil
            self?.compactIfIdle()
        }
    }

    private func compactIfIdle() {
        guard isExpanded, !isHoveringExpanded, !pointerIsInExpandedInteractionZone else { return }
        compactNow()
    }

    private func cancelPendingCompact() {
        pendingCompactTask?.cancel()
        pendingCompactTask = nil
    }

    private func startPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expandIfPointerIsInTopHotZone() }
        }
        RunLoop.main.add(pointerTimer!, forMode: .common)
    }

    private func expandIfPointerIsInTopHotZone() {
        if !isExpanded {
            guard let screen = screenWhoseTopHotZoneContainsPointer() else { return }
            expandNow(on: screen)
        } else if pointerIsInExpandedInteractionZone {
            cancelPendingCompact()
        } else if !isHoveringExpanded {
            scheduleCompactIfIdle()
        }
    }

    private func requestPresentation(_ presentation: Presentation, on screen: NSScreen) {
        desiredPresentation = presentation
        presentationScreen = screen
        guard presentationTask == nil else { return }

        presentationTask = Task { @MainActor [weak self] in
            await self?.drainPresentationRequests()
        }
    }

    private func drainPresentationRequests() async {
        defer { presentationTask = nil }

        while !Task.isCancelled {
            guard let notch else { return }
            let requestedPresentation = desiredPresentation
            let requestedScreen = presentationScreen ?? preferredScreen

            switch requestedPresentation {
            case .compact:
                await notch.compact(on: requestedScreen)
            case .expanded:
                await notch.expand(on: requestedScreen)
            }

            let requestIsCurrent = desiredPresentation == requestedPresentation
                && presentationScreen?.frame == requestedScreen.frame
            if requestIsCurrent { return }
        }
    }

    private func screenContainingPointer() -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = VibeBarHoverGeometry.screenIndex(
            containing: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame)
        ) else { return nil }
        return screens[index]
    }

    private func screenWhoseTopHotZoneContainsPointer() -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = VibeBarHoverGeometry.screenIndex(
            withTopHotZoneContaining: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame)
        ) else { return nil }
        return screens[index]
    }

    private var pointerIsInExpandedInteractionZone: Bool {
        VibeBarHoverGeometry.screenIndex(
            withExpandedInteractionZoneContaining: NSEvent.mouseLocation,
            screenFrames: NSScreen.screens.map(\.frame)
        ) != nil
    }

    private var preferredScreen: NSScreen {
        presentationScreen ?? screenContainingPointer() ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
