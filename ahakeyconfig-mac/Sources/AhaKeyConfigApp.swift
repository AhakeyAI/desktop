import AppKit
import SwiftUI
import AVFoundation
import Speech
import UserNotifications
import VibeBar

@main
struct AhaKeyConfigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bleManager = AhaKeyBLEManager()
    @State private var vibeBarBridge = VibeBarBridge()

    var body: some Scene {
        WindowGroup("AhaKey Studio") {
            ContentView(bleManager: bleManager)
                .frame(minWidth: 1180, minHeight: 680)
                .onAppear {
                    vibeBarBridge.attach(bleManager: bleManager) { [weak appDelegate] in
                        appDelegate?.reopenMainWindow()
                    }
                    VibeBarController.shared.start(state: vibeBarBridge.state)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            // 主程序只有一个工作区，禁用 Command-N，避免 WindowGroup 累积多个完整视图树。
            CommandGroup(replacing: .newItem) { }
        }

        if #available(macOS 13.0, *) {
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
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例：检查是否已有实例在运行
        let bundleID = Bundle.main.bundleIdentifier ?? "lab.jawa.ahakeyconfig"
        let currentBundlePath = Bundle.main.bundlePath
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            let otherInstances = running.filter { $0 != NSRunningApplication.current }
            let sameBundleInstance = otherInstances.first { app in
                app.bundleURL?.path == currentBundlePath
            }

            if let existing = sameBundleInstance {
                existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                NSApp.terminate(nil)
                return
            }

            for stale in otherInstances {
                stale.terminate()
            }
        }

        // 检查签名是否变化，如果变化则自动重置麦克风权限
        PermissionSignatureChecker.checkAndResetOnSignatureChange { success in
            DispatchQueue.main.async {
                if success {
                    let alert = NSAlert()
                    alert.messageText = "检测到应用签名变化"
                    alert.informativeText = "麦克风权限已自动重置，下次点击「申请」按钮时会弹出系统授权对话框。"
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }

        UNUserNotificationCenter.current().delegate = self

        VoiceRelayService.shared.start()
        NativeSpeechTranscriptionService.shared.start()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
        if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isMiniaturized }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
}
