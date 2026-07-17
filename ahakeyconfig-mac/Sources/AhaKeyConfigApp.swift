import AppKit
import AhaKeyConfigShared
import SwiftUI
import AVFoundation
import Speech
import UserNotifications

@main
struct AhaKeyConfigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bleManager = AhaKeyBLEManager()

    init() {
        AppLanguageInitializer.applySystemLanguageIfNeeded()
    }

    var body: some Scene {
        WindowGroup("AhaKey Studio") {
            ContentView(bleManager: bleManager)
                .frame(minWidth: 1180, minHeight: 680)
        }
        .windowStyle(.titleBar)

        if #available(macOS 13.0, *) {
            MenuBarExtra("AhaKey", systemImage: "keyboard") {
                Button(NSLocalizedString("打开主窗口", comment: "")) {
                    appDelegate.reopenMainWindow()
                }

                Divider()

                let ppm = PowerProtectionManager.shared
                Button(ppm.enabled ? NSLocalizedString("关闭合盖运行", comment: "") : NSLocalizedString("开启合盖运行", comment: "")) {
                    ppm.enabled.toggle()
                }

                Button(NSLocalizedString("立即恢复正常休眠", comment: "")) {
                    ppm.deactivateAll()
                    ppm.enabled = false
                }
                .disabled(!ppm.isProtectionActive)

                Divider()

                Button(NSLocalizedString("退出 AhaKey Studio", comment: "")) {
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
                    alert.messageText = NSLocalizedString("检测到应用签名变化", comment: "")
                    alert.informativeText = NSLocalizedString("麦克风权限已自动重置，下次点击「申请」按钮时会弹出系统授权对话框。", comment: "")
                    alert.addButton(withTitle: NSLocalizedString("确定", comment: ""))
                    alert.runModal()
                }
            }
        }

        UNUserNotificationCenter.current().delegate = self

        PowerProtectionManager.shared.configureAsApp()
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

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort cleanup: SIGKILL can't be caught, but normal quit/updates
        // will release assertions and the virtual display lock.
        _ = PowerProtectionManager.shared.deactivateAll()
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
