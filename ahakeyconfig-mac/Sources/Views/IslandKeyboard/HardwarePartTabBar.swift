import SwiftUI

/// 硬件 Inspector 顶部元件分段：与画布 `selectedPart` 双向同步。
struct HardwarePartTabBar: View {
    let parts: [AhaKeyStudioPart]
    @Binding var selection: AhaKeyStudioPart
    var dirtyParts: Set<AhaKeyStudioPart> = []
    var isEmbedded: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(parts) { part in
                    partButton(part)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(isEmbedded ? AhaKeyStudioEmbeddedTheme.cardBackground : Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func partButton(_ part: AhaKeyStudioPart) -> some View {
        let isSelected = selection == part
        let isDirty = dirtyParts.contains(part)
        return Button {
            selection = part
        } label: {
            HStack(spacing: 4) {
                Image(systemName: part.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(part.tabTitle)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                if isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(
                isSelected
                    ? (isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : Color.primary)
                    : (isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : Color.secondary)
            )
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? (isEmbedded ? AhaKeyStudioEmbeddedTheme.controlFill : Color.accentColor.opacity(0.14))
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? (isEmbedded ? AhaKeyStudioEmbeddedTheme.accentBlue.opacity(0.55) : Color.accentColor.opacity(0.35))
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("\(part.title) · \(part.subtitle)")
    }
}
