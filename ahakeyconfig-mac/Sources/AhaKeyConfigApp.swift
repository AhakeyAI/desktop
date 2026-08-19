import AppKit
import AhaKeyConfigShared
import Combine
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
    /// 防休眠与进程检测的常驻订阅（应用级，窗口关闭不影响）。
    private var powerProtectionCancellable: AnyCancellable?

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
        // 进程检测生命周期移出 SwiftUI：App 启动即开始，窗口关闭检测继续运行（它驱动防休眠）。
        // 防休眠接线也放这里常驻，不再依赖 AhaKeyStudioView 的 onAppear/onDisappear/onChange。
        let processDetector = ProcessDetector.shared
        processDetector.start()
        powerProtectionCancellable = processDetector.$isAnyTargetRunning
            .removeDuplicates()
            .sink { running in
                let ppm = PowerProtectionManager.shared
                if running {
                    ppm.begin(.aiCodingIdleProcess)
                    ppm.begin(.aiCodingLidCloseProcess)
                } else {
                    ppm.end(.aiCodingIdleProcess)
                    ppm.end(.aiCodingLidCloseProcess)
                }
            }
        VoiceRelayService.shared.start()
        NativeSpeechTranscriptionService.shared.start()

        // 启动恢复登录态后主动拉一次云端 profile（配额/余额），失败自动重试，
        // 不再依赖用户手动打开云端账号弹窗。
        Task { @MainActor in
            let account = CloudAccountManager.shared
            if account.isLoggedIn {
                account.refreshProfile(showAlertOnFailure: false, retryDelays: [2, 5, 10])
            }
        }
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
