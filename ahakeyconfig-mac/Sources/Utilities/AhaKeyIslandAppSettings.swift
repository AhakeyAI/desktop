import AppKit
import Foundation
import ServiceManagement

/// 灵动岛相关的应用级偏好（Dock / 登录项）。
enum AhaKeyIslandAppSettings {
    static let showInDockKey = "ahakey.island.showInDock"
    static let openAtLoginKey = "ahakey.island.openAtLogin"

    static var showInDock: Bool {
        get {
            if UserDefaults.standard.object(forKey: showInDockKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showInDockKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showInDockKey)
            applyDockVisibility(newValue)
        }
    }

    static var openAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return UserDefaults.standard.bool(forKey: openAtLoginKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: openAtLoginKey)
            applyOpenAtLogin(newValue)
        }
    }

    static func applyStoredPreferences() {
        applyDockVisibility(showInDock)
        if UserDefaults.standard.object(forKey: openAtLoginKey) != nil {
            applyOpenAtLogin(UserDefaults.standard.bool(forKey: openAtLoginKey))
        }
    }

    private static func applyDockVisibility(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func applyOpenAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 登录项权限可能被系统拒绝；保留 UserDefaults 值供下次重试。
            NSLog("AhaKey openAtLogin failed: \(error.localizedDescription)")
        }
    }
}
