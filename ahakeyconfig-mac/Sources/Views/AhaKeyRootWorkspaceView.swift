import SwiftUI

enum AhaKeyRootWorkspaceMode: String, CaseIterable, Identifiable {
    case classic
    case newWorkbench

    static let storageKey = "AhaKey.RootWorkspaceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            "IDE工作台"
        case .newWorkbench:
            "Agent工作台"
        }
    }
}

struct AhaKeyRootWorkspaceView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @AppStorage(AhaKeyRootWorkspaceMode.storageKey) private var modeRawValue = AhaKeyRootWorkspaceMode.classic.rawValue
    @AppStorage(AhaKeyAppearanceMode.storageKey) private var appearanceModeRaw = AhaKeyAppearanceMode.defaultMode.rawValue

    private var mode: AhaKeyRootWorkspaceMode {
        AhaKeyRootWorkspaceMode(rawValue: modeRawValue) ?? .classic
    }

    private var appearanceMode: AhaKeyAppearanceMode {
        AhaKeyAppearanceMode(rawValue: appearanceModeRaw) ?? .defaultMode
    }

    private var modeBinding: Binding<AhaKeyRootWorkspaceMode> {
        Binding(
            get: { mode },
            set: { modeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: AhaKeyUI.Spacing.shell) {
            workspaceToolbar
            Group {
                switch mode {
                case .classic:
                    AhaKeyStudioView(bleManager: bleManager)
                case .newWorkbench:
                    AhaKeyWorkbenchView(bleManager: bleManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyStudioNavigate)) { notification in
            guard let raw = notification.userInfo?[StudioNavigationUserInfoKey.section] as? String,
                  let section = StudioNavigationSection(rawValue: raw) else { return }

            switch section {
            case .voiceAgent, .approve, .voice:
                modeRawValue = AhaKeyRootWorkspaceMode.newWorkbench.rawValue
            case .device, .oled:
                modeRawValue = AhaKeyRootWorkspaceMode.classic.rawValue
            }
        }
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 12) {
            Picker("工作台", selection: modeBinding) {
                ForEach(AhaKeyRootWorkspaceMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer(minLength: 0)

            Button {
                appearanceModeRaw = appearanceMode.next.rawValue
            } label: {
                Image(systemName: appearanceMode.systemImage)
            }
            .buttonStyle(AhaKeyIconButtonStyle())
            .help(appearanceMode.title)
        }
        .padding(.horizontal, AhaKeyUI.Spacing.page)
        .padding(.vertical, 10)
        .background(AhaKeyUI.ColorToken.card)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AhaKeyUI.ColorToken.border)
                .frame(height: 1)
        }
    }
}
