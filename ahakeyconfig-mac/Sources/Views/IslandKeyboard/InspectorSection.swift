import SwiftUI

/// Inspector 二级模块：标题 + 内容区（1 级为元件名 `inspectorHeader`）。
struct InspectorSection<Content: View>: View {
    let title: String
    var isEmbedded: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: isEmbedded ? 13 : 14, weight: .semibold))
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : Color.primary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEmbedded ? AhaKeyStudioEmbeddedTheme.controlFill : Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}
