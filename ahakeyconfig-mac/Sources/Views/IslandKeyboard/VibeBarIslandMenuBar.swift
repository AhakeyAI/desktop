import SwiftUI

/// Vibe Island 顶栏菜单按钮（对齐 VibeBar.app `openedHeaderButtons`）。
struct VibeBarIslandMenuBar: View {
    @Binding var isSoundMuted: Bool
    var onOpenMainWindow: () -> Void
    var onQuit: () -> Void

    private let buttonSize: CGFloat = 22
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            menuIconButton(
                systemName: isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: isSoundMuted ? .orange.opacity(0.92) : .white.opacity(0.62),
                accessibilityLabel: isSoundMuted ? "开启提示音" : "关闭提示音"
            ) {
                isSoundMuted.toggle()
                if !isSoundMuted {
                    VibeBarIslandSoundSettings.playInteractionIfEnabled()
                }
            }

            menuIconButton(
                systemName: "gearshape.fill",
                tint: .white.opacity(0.62),
                accessibilityLabel: "打开客户端主界面"
            ) {
                onOpenMainWindow()
            }

            menuIconButton(
                systemName: "power",
                tint: .white.opacity(0.62),
                accessibilityLabel: "退出应用"
            ) {
                onQuit()
            }
        }
    }

    private func menuIconButton(
        systemName: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: buttonSize, height: buttonSize)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
