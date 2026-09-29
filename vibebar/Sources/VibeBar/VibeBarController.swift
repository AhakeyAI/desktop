import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
public final class VibeBarController {
    public static let shared = VibeBarController()

    private var notch: (any DynamicNotchControllable)?
    private var pendingCompactTask: Task<Void, Never>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pointerUpdatePending = false
    private var isExpanded = false
    private weak var state: VibeBarState?
    private(set) var presentationScreen: NSScreen?
    private var leadingFrame: CGRect?
    private var trailingFrame: CGRect?
    private var compactScreen: NSScreen?
    private var expandedContentFrame: CGRect?
    private var windowProvider: () -> NSWindow? = { nil }
    private var desiredPresentation: Presentation = .compact
    private var presentationTask: Task<Void, Never>?

    private enum Presentation: Equatable {
        case compact
        case expanded
    }

    init() {}

    /// 在主 app 启动后调用一次。多次调用是空操作。
    public func start(state: VibeBarState) {
        guard notch == nil else { return }
        self.state = state

        let notch = DynamicNotch(
            hoverBehavior: [],
            style: .notch
        ) { [weak self] in
            VibeBarExpandedMenu(
                state: state,
                onAppear: { self?.expandedMenuAppeared() },
                onHoverChanged: { self?.expandedHoverChanged($0) },
                onFrameChanged: { frame, screen in
                    self?.presentationScreen = screen
                    self?.expandedContentFrame = frame
                    self?.schedulePointerUpdate()
                },
                onCompact: { self?.compactNow() },
                onOpenMain: { state.onOpenMainWindow?() }
            )
        } compactLeading: { [weak self] in
            VibeBarCompactKeyboardItem(state: state,
                onFrameChanged: { self?.compactFrameChanged($0, screen: $1, leading: true) })
        } compactTrailing: { [weak self] in
            VibeBarCompactLeverItem(state: state,
                onFrameChanged: { self?.compactFrameChanged($0, screen: $1, leading: false) })
        }

        self.windowProvider = { [weak notch] in notch?.windowController?.window }
        self.notch = notch
        presentationScreen = screenContainingPointer() ?? NSScreen.main ?? NSScreen.screens.first
        compactNow()
        startPointerTracking()
    }

    public func stop() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        pendingCompactTask?.cancel()
        pendingCompactTask = nil
        presentationTask?.cancel()
        presentationTask = nil
        notch = nil
        state = nil
        presentationScreen = nil
        leadingFrame = nil
        trailingFrame = nil
        compactScreen = nil
        expandedContentFrame = nil
        windowProvider = { nil }
    }

    // MARK: - Notch state machine

    private func compactNow() {
        cancelPendingCompact()
        if isExpanded { leadingFrame = nil; trailingFrame = nil }
        isExpanded = false
        setMousePassthrough(true)
        requestPresentation(.compact, on: presentationScreen ?? preferredScreen)
    }

    private func expandNow(on screen: NSScreen? = nil) {
        cancelPendingCompact()
        isExpanded = true
        requestPresentation(.expanded, on: screen ?? screenContainingPointer() ?? preferredScreen)
    }

    private func expandedMenuAppeared() {
        cancelPendingCompact()
        isExpanded = true
    }

    private func expandedHoverChanged(_ hovering: Bool) {
        if hovering, pointerIsInExpandedInteractionZone {
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
        guard isExpanded, !pointerIsInExpandedInteractionZone else { return }
        compactNow()
    }

    private func cancelPendingCompact() {
        pendingCompactTask?.cancel()
        pendingCompactTask = nil
    }

    private func startPointerTracking() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.schedulePointerUpdate() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            Task { @MainActor in self?.schedulePointerUpdate() }
            return event
        }
        schedulePointerUpdate()
    }

    private func schedulePointerUpdate() {
        guard !pointerUpdatePending else { return }
        pointerUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pointerUpdatePending = false
            self.updatePointerPresentation()
        }
    }

    private func setMousePassthrough(_ passthrough: Bool) {
        guard let window = windowProvider(), window.ignoresMouseEvents != passthrough else { return }
        window.ignoresMouseEvents = passthrough
    }

    private func updatePointerPresentation() {
        if !isExpanded {
            // Compact panels never receive raw hover events from the library.
            setMousePassthrough(true)
            guard pointerCanExpand else { return }
            expandNow(on: compactScreen)
        } else if pointerIsInExpandedInteractionZone {
            setMousePassthrough(false)
            cancelPendingCompact()
        } else {
            setMousePassthrough(true)
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

    func compactFrameChanged(_ frame: CGRect, screen: NSScreen, leading: Bool) {
        // DynamicNotchKit can rebuild its window on another screen independently
        // of our presentation requests (display detach / primary-display change).
        if presentationScreen?.frame != screen.frame { expandedContentFrame = nil }
        presentationScreen = screen
        if compactScreen?.frame != screen.frame {
            leadingFrame = nil
            trailingFrame = nil
            compactScreen = screen
        }
        if leading { leadingFrame = frame } else { trailingFrame = frame }
        schedulePointerUpdate()
    }

    private var pointerCanExpand: Bool {
        guard let screen = compactScreen, windowProvider()?.isVisible == true,
              presentationScreen?.frame == screen.frame else { return false }
        let hasNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        let height = hasNotch ? screen.safeAreaInsets.top : screen.frame.maxY - screen.visibleFrame.maxY
        let frame = VibeBarHoverGeometry.compactFrame(
            leading: leadingFrame, trailing: trailingFrame, screen: screen.frame, height: height)
        let hit = VibeBarHoverGeometry.shouldExpand(
            at: NSEvent.mouseLocation, compactFrame: frame, pressedMouseButtons: NSEvent.pressedMouseButtons)
        return hit
    }

    private var pointerIsInExpandedInteractionZone: Bool {
        guard let content = expandedContentFrame, let screen = presentationScreen,
              windowProvider()?.isVisible == true else { return false }
        return VibeBarHoverGeometry.contains(NSEvent.mouseLocation,
            frame: VibeBarHoverGeometry.expandedFrame(content: content, screen: screen.frame),
            topRadius: 15, bottomRadius: 20)
    }

    private var preferredScreen: NSScreen {
        presentationScreen ?? screenContainingPointer() ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
