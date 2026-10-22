import SwiftUI

/// Text-labelled groups preserve the Inspector's controls without relying on
/// the native GroupBox's synthesized attributed-only accessibility heading.
struct StudioInspectorSection<Content: View>: View {
    private let title: String?
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = NSLocalizedString(title, comment: "")
        self.content = content()
    }

    init(@ViewBuilder content: () -> Content) {
        title = nil
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
    }
}
