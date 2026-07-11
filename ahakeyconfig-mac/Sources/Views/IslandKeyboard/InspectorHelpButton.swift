import SwiftUI

/// 硬件 Inspector 问号帮助：悬停即展开，移开即收起。
struct InspectorHelpButton: View {
    var title: String = "如何使用"
    var lines: [String]
    var isEmbedded: Bool = true
    var width: CGFloat = 280
    var arrowEdge: Edge = .leading

    @State private var isPresented = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "questionmark.circle")
            .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : Color.secondary)
            .imageScale(.medium)
            .contentShape(Rectangle())
            .onHover { hovering in
                dismissTask?.cancel()
                dismissTask = nil
                if hovering {
                    isPresented = true
                } else {
                    // 极短延迟，避免移向 popover 瞬间误关造成闪烁
                    dismissTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 60_000_000)
                        guard !Task.isCancelled else { return }
                        isPresented = false
                    }
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Divider()
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                .font(.callout)
                .padding(16)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onHover { hovering in
                    dismissTask?.cancel()
                    dismissTask = nil
                    if hovering {
                        isPresented = true
                    } else {
                        dismissTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 60_000_000)
                            guard !Task.isCancelled else { return }
                            isPresented = false
                        }
                    }
                }
            }
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("将指针悬停以查看说明")
    }
}
