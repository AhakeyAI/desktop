import SwiftUI

struct StudioKeyboardWriteLabel: View {
    let isReading: Bool
    var isBusy = false
    var systemImage: String? = nil
    var writeTitle = NSLocalizedString("写入键盘", comment: "")

    var body: some View {
        if isReading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("设置读取中")
            }
        } else {
            let title = isBusy ? NSLocalizedString("处理中…", comment: "") : writeTitle
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
}
