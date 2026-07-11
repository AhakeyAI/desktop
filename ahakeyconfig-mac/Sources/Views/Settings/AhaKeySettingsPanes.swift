import SwiftUI
import VibeBar

struct VoiceInputWorkspacePane: View {
    @State private var configSection: AhaKeyVoiceInputConfigSection = .history

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                AhaKeyVoiceInputSectionPicker(selection: $configSection)

                switch configSection {
                case .history:
                    AhaKeyVoiceHistoryPane()
                case .dictionary:
                    AhaKeyVoiceDictionaryPane()
                case .general:
                    AhaKeyVoiceGeneralConfigPane()
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.contentPadding)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AhakeySettingsTheme.contentBackground)
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeySettingsSelectTab)) { notification in
            guard let tabRaw = notification.userInfo?[StudioNavigationUserInfoKey.tab] as? String,
                  tabRaw == AhaKeySettingsTab.voiceInput.rawValue,
                  let sectionRaw = notification.userInfo?[StudioNavigationUserInfoKey.voiceSection] as? String,
                  let section = AhaKeyVoiceInputConfigSection(rawValue: sectionRaw) else { return }
            configSection = section
        }
    }
}

struct HardwareStudioHost: View {
    @ObservedObject var bleManager: AhaKeyBLEManager

    var body: some View {
        AhaKeyStudioView(bleManager: bleManager, presentation: .embeddedClient)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentWorkbenchHost: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var islandState: VibeBarState
    @Binding var section: AhaKeyAgentConfigSection

    var body: some View {
        AhaKeyAgentWorkspacePane(bleManager: bleManager, islandState: islandState, section: $section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
