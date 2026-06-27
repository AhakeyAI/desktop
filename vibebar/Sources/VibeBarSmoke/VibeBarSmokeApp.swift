import AppKit
import SwiftUI
import VibeBar

@main
struct VibeBarSmokeApp: App {
    @NSApplicationDelegateAdaptor(SmokeDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class SmokeDelegate: NSObject, NSApplicationDelegate {
    private let state = VibeBarState()
    private var demoTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        state.keyboardConnected = true
        state.batteryLevel = 75
        state.deviceName = "AhaKey-X1 (smoke)"
        state.leverIsAuto = true
        state.leverKnown = true
        state.voiceListening = true
        state.voiceRecording = false
        state.onOpenMainWindow = {
            NSLog("VibeBarSmoke: onOpenMainWindow tapped")
        }

        VibeBarController.shared.start(state: state)

        // 周期性翻转一些状态，方便肉眼验证 UI 真的在跟着 state 变
        demoTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state.leverIsAuto.toggle()
                self.state.voiceRecording.toggle()
                self.state.batteryLevel = max(5, (self.state.batteryLevel + 95) % 100)
            }
        }
    }
}
