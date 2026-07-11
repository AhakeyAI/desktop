import SwiftUI

/// Studio Inspector 折叠区：与灵动岛 `AhaKeySettingsDisclosureSection` 同构，色随嵌入/独立主题。
struct AhaKeyStudioDisclosureSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var isEmbedded: Bool = true
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(primaryText)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(tertiaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(controlFill)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var primaryText: Color {
        isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : Color.primary
    }

    private var tertiaryText: Color {
        isEmbedded ? AhaKeyStudioEmbeddedTheme.tertiaryText : Color.secondary
    }

    private var controlFill: Color {
        isEmbedded ? AhaKeyStudioEmbeddedTheme.controlFill : Color(nsColor: .controlBackgroundColor)
    }
}
