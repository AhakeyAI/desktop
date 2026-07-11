import SwiftUI
import VibeBar

/// Settings「Agent」根容器：助手 / 联动 / 设置。
struct AhaKeyAgentWorkspacePane: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var islandState: VibeBarState
    @Binding var section: AhaKeyAgentConfigSection

    var body: some View {
        VStack(spacing: 0) {
            AhaKeyAgentSectionPicker(selection: $section)
                .padding(.horizontal, AhakeySettingsTheme.contentPadding)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Group {
                switch section {
                case .assistant:
                    // Chatbot：消息区可滚、输入贴底，不能包在整页 ScrollView 里。
                    AhaKeyAgentAssistantPane(bleManager: bleManager)
                        .padding(.horizontal, AhakeySettingsTheme.contentPadding)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .status:
                    ScrollView(.vertical, showsIndicators: true) {
                        AhaKeyAgentStatusPane(bleManager: bleManager)
                            .padding(.horizontal, AhakeySettingsTheme.contentPadding)
                            .padding(.bottom, 28)
                    }
                case .general:
                    ScrollView(.vertical, showsIndicators: true) {
                        AhaKeyAgentGeneralPane(islandState: islandState)
                            .padding(.horizontal, AhakeySettingsTheme.contentPadding)
                            .padding(.bottom, 28)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AhakeySettingsTheme.contentBackground)
    }
}
