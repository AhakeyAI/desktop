import AppKit
import SwiftUI
import AVFoundation
import Speech

@main
struct AhaKeyConfigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bleManager = AhaKeyBLEManager()

    var body: some Scene {
        WindowGroup("AhaKey Studio") {
            ContentView(bleManager: bleManager)
                .frame(minWidth: 1180, minHeight: 680)
        }
        .windowStyle(.titleBar)

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

final class AppDelegate: NSObject, NSApplicationDelegate {
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
                    // 权限已重置，下次点击申请会弹出原生授权弹窗
                    let alert = NSAlert()
                    alert.messageText = "检测到应用签名变化"
                    alert.informativeText = "麦克风权限已自动重置，下次点击「申请」按钮时会弹出系统授权对话框。"
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
                
                // 延迟触发兜底请求：先麦克风，用户响应后再请求语音识别
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let micUndetermined: Bool
                    if #available(macOS 14.0, *) {
                        micUndetermined = AVAudioApplication.shared.recordPermission == .undetermined
                    } else {
                        micUndetermined = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
                    }
                    if micUndetermined {
                        if #available(macOS 14.0, *) {
                            AVAudioApplication.requestRecordPermission { _ in
                                Task { @MainActor in
                                    if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                                        SFSpeechRecognizer.requestAuthorization { _ in }
                                    }
                                }
                            }
                        } else {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in
                                Task { @MainActor in
                                    if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                                        SFSpeechRecognizer.requestAuthorization { _ in }
                                    }
                                }
                            }
                        }
                    } else if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                        SFSpeechRecognizer.requestAuthorization { _ in }
                    }
                }
            }
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
        if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isMiniaturized }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
}
