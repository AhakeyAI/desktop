import Foundation
import SwiftUI

enum StudioNavigationSection: String {
    case voiceAgent
    case device
    case approve
    case oled
    case voice
}

@MainActor
final class StudioNavigationRouter {
    static let shared = StudioNavigationRouter()

    private init() {}

    func navigate(to section: StudioNavigationSection) {
        navigate(to: section, part: nil)
    }

    func navigate(to section: StudioNavigationSection, part: AhaKeyStudioPart?) {
        var userInfo: [String: Any] = [StudioNavigationUserInfoKey.section: section.rawValue]
        if let part {
            userInfo[StudioNavigationUserInfoKey.part] = part.rawValue
        }
        NotificationCenter.default.post(
            name: .ahaKeyStudioNavigate,
            object: nil,
            userInfo: userInfo
        )
    }

    func selectSettingsTab(_ tab: AhaKeySettingsTab) {
        NotificationCenter.default.post(
            name: .ahaKeySettingsSelectTab,
            object: nil,
            userInfo: [StudioNavigationUserInfoKey.tab: tab.rawValue]
        )
    }

    func selectAgentSection(_ section: AhaKeyAgentConfigSection) {
        NotificationCenter.default.post(
            name: .ahaKeySettingsSelectTab,
            object: nil,
            userInfo: [
                StudioNavigationUserInfoKey.tab: AhaKeySettingsTab.agent.rawValue,
                StudioNavigationUserInfoKey.agentSection: section.rawValue
            ]
        )
    }

    func selectVoiceSection(_ section: AhaKeyVoiceInputConfigSection) {
        NotificationCenter.default.post(
            name: .ahaKeySettingsSelectTab,
            object: nil,
            userInfo: [
                StudioNavigationUserInfoKey.tab: AhaKeySettingsTab.voiceInput.rawValue,
                StudioNavigationUserInfoKey.voiceSection: section.rawValue
            ]
        )
    }

    /// 打开 Agent · 设置（Pet 外观主入口）。
    func openPetAppearanceSettings() {
        selectAgentSection(.general)
    }

    /// 兼容旧调用名。
    func openOledPetSettings() {
        openPetAppearanceSettings()
    }

    /// 打开左下角「我的设备」详情页。
    func openDeviceManagement(showDetail: Bool = true) {
        NotificationCenter.default.post(
            name: .ahaKeyOpenMyDevices,
            object: nil,
            userInfo: [StudioNavigationUserInfoKey.openDeviceDetail: showDetail]
        )
    }

    func openUserCenter(section: AhaKeyUserCenterSection = .account) {
        NotificationCenter.default.post(
            name: .ahaKeyOpenUserCenter,
            object: nil,
            userInfo: [StudioNavigationUserInfoKey.userCenterSection: section.rawValue]
        )
    }

    func openPluginMarket(section: AhakeyPluginMarketSection = .mine) {
        NotificationCenter.default.post(
            name: .ahaKeyOpenPluginMarket,
            object: nil,
            userInfo: [StudioNavigationUserInfoKey.pluginMarketSection: section.rawValue]
        )
    }
}

enum StudioNavigationUserInfoKey {
    static let section = "section"
    static let tab = "tab"
    static let part = "part"
    static let workbenchTab = "workbenchTab"
    static let keyRole = "keyRole"
    static let openDeviceDetail = "openDeviceDetail"
    static let agentSection = "agentSection"
    static let voiceSection = "voiceSection"
    static let dynamicIslandRoute = "dynamicIslandRoute"
    static let userCenterSection = "userCenterSection"
    static let pluginMarketSection = "pluginMarketSection"
}

extension Notification.Name {
    static let ahaKeyStudioNavigate = Notification.Name("lab.jawa.ahakeyconfig.studioNavigate")
    static let ahaKeySettingsSelectTab = Notification.Name("lab.jawa.ahakeyconfig.settingsSelectTab")
    static let ahaKeyStudioSelectPart = Notification.Name("lab.jawa.ahakeyconfig.studioSelectPart")
    static let ahaKeyStudioShowDeviceInfo = Notification.Name("lab.jawa.ahakeyconfig.studioShowDeviceInfo")
    static let ahaKeyReopenMainWindow = Notification.Name("lab.jawa.ahakeyconfig.reopenMainWindow")
    static let ahaKeyOpenUserCenter = Notification.Name("lab.jawa.ahakeyconfig.openUserCenter")
    static let ahaKeyOpenMyDevices = Notification.Name("lab.jawa.ahakeyconfig.openMyDevices")
    static let ahaKeyOpenPluginMarket = Notification.Name("lab.jawa.ahakeyconfig.openPluginMarket")
}

/// 监听重新打开主窗口请求；并把 `openWindow` 注册到 AppDelegate，避免主窗口关闭后无人响应。
struct MainWindowReopenHelper: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                AppDelegate.registerOpenMainWindow { [openWindow] in
                    openWindow(id: "main")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ahaKeyReopenMainWindow)) { _ in
                openWindow(id: "main")
            }
    }
}
