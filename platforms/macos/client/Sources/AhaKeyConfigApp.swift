import AppKit
import SwiftUI

@main
struct AhaKeyConfigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bleManager = AhaKeyBLEManager()

    var body: some Scene {
        Window("AhaKey Studio", id: "main") {
            ContentView(bleManager: bleManager)
                .frame(minWidth: 1280, minHeight: 820)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra("AhaKey", systemImage: "keyboard") {
            Button("打开主窗口") {
                appDelegate.reopenMainWindow()
            }

            Divider()

            Button("退出 AhaKey Studio") {
                NSApp.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例：检查是否已有实例在运行
        let bundleID = Bundle.main.bundleIdentifier ?? "lab.jawa.ahakeyconfig"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            if let existing = running.first(where: { $0 != NSRunningApplication.current }) {
                existing.activate()
            }
            NSApp.terminate(nil)
        }

        VoiceRelayService.shared.start()
        NativeSpeechTranscriptionService.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        VoiceRelayService.shared.refreshPermissions()
        NativeSpeechTranscriptionService.shared.refreshPermissions()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            reopenMainWindow()
        }
        return true
    }

    func reopenMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
}
