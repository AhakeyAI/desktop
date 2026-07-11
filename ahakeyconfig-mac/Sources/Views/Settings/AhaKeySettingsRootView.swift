import SwiftUI
import VibeBar

struct AhaKeySettingsRootView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var islandState: VibeBarState

    @State private var selectedTab: AhaKeySettingsTab = .hardware
    @State private var dynamicIslandRoute: AhaKeyDynamicIslandSettingsRoute = .root
    @State private var agentSection: AhaKeyAgentConfigSection = .assistant
    @State private var showsPluginMarket = false
    @State private var pluginMarketSection: AhakeyPluginMarketSection = .mine
    @State private var showsUserCenter = false
    @State private var userCenterSection: AhaKeyUserCenterSection = .account
    @State private var showsMyDevices = false
    @State private var showsDeviceDetail = false

    @AppStorage(AhaKeyAppearanceMode.storageKey) private var appearanceModeRaw = AhaKeyAppearanceMode.defaultMode.rawValue
    @AppStorage(AhakeyGeneralSettingsStore.languageKey) private var languageRaw = AhaKeyAppLanguage.system.rawValue
    @AppStorage(AhakeyGeneralSettingsStore.regionKey) private var regionRaw = AhaKeyAppRegion.system.rawValue

    private let brandName = "AhaKey"

    private var appearanceMode: AhaKeyAppearanceMode {
        AhaKeyAppearanceMode(rawValue: appearanceModeRaw) ?? .defaultMode
    }

    private var resolvedLocale: Locale {
        let language = AhaKeyAppLanguage(rawValue: languageRaw) ?? .system
        let region = AhaKeyAppRegion(rawValue: regionRaw) ?? .system
        return AhaKeyLocaleResolver.locale(language: language, region: region)
    }

    var body: some View {
        AhakeySettingsRootChrome {
            AhakeySettingsFlatSidebar(
                bleManager: bleManager,
                selection: $selectedTab,
                onUserTap: { openUserCenter(.account) },
                onDeviceTap: { openMyDevices() }
            )
            .onChange(of: selectedTab) { _ in
                showsPluginMarket = false
                showsUserCenter = false
                showsMyDevices = false
                showsDeviceDetail = false
            }
        } detail: {
            VStack(spacing: 0) {
                AhakeySettingsGlobalTopBar(onPluginMarketTap: { openPluginMarket(.mine) })
                detailView
            }
        }
        .frame(minWidth: 900, idealWidth: 1180, minHeight: 560, idealHeight: 680)
        .preferredColorScheme(appearanceMode.colorScheme)
        .environment(\.locale, resolvedLocale)
        .sheet(isPresented: $showsUserCenter) {
            AhaKeyUserCenterPane(
                bleManager: bleManager,
                section: $userCenterSection,
                onClose: { showsUserCenter = false }
            )
            .frame(width: 880, height: 620)
            .preferredColorScheme(appearanceMode.colorScheme)
            .environment(\.locale, resolvedLocale)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyStudioNavigate)) { notification in
            handleStudioNavigation(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeySettingsSelectTab)) { notification in
            if let raw = notification.userInfo?[StudioNavigationUserInfoKey.tab] as? String,
               let tab = AhaKeySettingsTab(rawValue: raw) {
                selectedTab = tab
                showsPluginMarket = false
                showsUserCenter = false
                showsMyDevices = false
                showsDeviceDetail = false
                if tab == .agent,
                   let sectionRaw = notification.userInfo?[StudioNavigationUserInfoKey.agentSection] as? String,
                   let section = AhaKeyAgentConfigSection(rawValue: sectionRaw) {
                    agentSection = section
                }
                if tab == .dynamicIsland,
                   let routeRaw = notification.userInfo?[StudioNavigationUserInfoKey.dynamicIslandRoute] as? String,
                   let route = AhaKeyDynamicIslandSettingsRoute(rawValue: routeRaw) {
                    dynamicIslandRoute = route
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyOpenUserCenter)) { notification in
            let section: AhaKeyUserCenterSection
            if let raw = notification.userInfo?[StudioNavigationUserInfoKey.userCenterSection] as? String,
               let parsed = AhaKeyUserCenterSection(rawValue: raw) {
                section = parsed
            } else {
                section = .account
            }
            openUserCenter(section)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyOpenPluginMarket)) { notification in
            let section: AhakeyPluginMarketSection
            if let raw = notification.userInfo?[StudioNavigationUserInfoKey.pluginMarketSection] as? String,
               let parsed = AhakeyPluginMarketSection(rawValue: raw) {
                section = parsed
            } else {
                section = .mine
            }
            openPluginMarket(section)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyOpenMyDevices)) { notification in
            let openDetail = (notification.userInfo?[StudioNavigationUserInfoKey.openDeviceDetail] as? Bool) ?? true
            openMyDevices(showDetail: openDetail)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if showsPluginMarket {
            AhakeyPluginMarketPane(
                section: $pluginMarketSection,
                onClose: { showsPluginMarket = false }
            )
        } else if showsMyDevices {
            AhaKeyDeviceManagementPane(
                bleManager: bleManager,
                showsDetail: $showsDeviceDetail,
                onClose: closeMyDevices
            )
        } else {
            switch selectedTab {
            case .dynamicIsland:
                AhaKeyDynamicIslandSettingsPane(
                    state: islandState,
                    route: $dynamicIslandRoute,
                    brandName: brandName
                )
            case .hardware:
                HardwareStudioHost(bleManager: bleManager)
            case .voiceInput:
                VoiceInputWorkspacePane()
            case .agent:
                AgentWorkbenchHost(bleManager: bleManager, islandState: islandState, section: $agentSection)
            }
        }
    }

    private func openUserCenter(_ section: AhaKeyUserCenterSection = .account) {
        userCenterSection = section
        showsUserCenter = true
    }

    private func openPluginMarket(_ section: AhakeyPluginMarketSection = .mine) {
        pluginMarketSection = section
        showsUserCenter = false
        showsMyDevices = false
        showsDeviceDetail = false
        showsPluginMarket = true
    }

    private func openMyDevices(showDetail: Bool = true) {
        showsPluginMarket = false
        showsUserCenter = false
        showsMyDevices = true
        showsDeviceDetail = showDetail
    }

    private func closeMyDevices() {
        showsMyDevices = false
        showsDeviceDetail = false
    }

    private func openHardware(part: AhaKeyStudioPart) {
        showsMyDevices = false
        showsDeviceDetail = false
        selectedTab = .hardware
        NotificationCenter.default.post(
            name: .ahaKeyStudioSelectPart,
            object: nil,
            userInfo: [StudioNavigationUserInfoKey.part: part.rawValue]
        )
    }

    private func handleStudioNavigation(_ notification: Notification) {
        guard let raw = notification.userInfo?[StudioNavigationUserInfoKey.section] as? String,
              let section = StudioNavigationSection(rawValue: raw) else { return }

        showsPluginMarket = false
        showsUserCenter = false

        switch section {
        case .voiceAgent:
            showsMyDevices = false
            showsDeviceDetail = false
            selectedTab = .agent
            agentSection = .assistant
        case .approve:
            openHardware(part: .key2)
        case .voice:
            openHardware(part: .key1)
        case .oled:
            openHardware(part: .oledDisplay)
        case .device:
            openMyDevices(showDetail: true)
        }

        if let partRaw = notification.userInfo?[StudioNavigationUserInfoKey.part] as? String,
           let part = AhaKeyStudioPart(rawValue: partRaw),
           selectedTab == .hardware {
            NotificationCenter.default.post(
                name: .ahaKeyStudioSelectPart,
                object: nil,
                userInfo: [StudioNavigationUserInfoKey.part: part.rawValue]
            )
        }
    }
}
