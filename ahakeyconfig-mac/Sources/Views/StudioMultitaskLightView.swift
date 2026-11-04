import SwiftUI

/// Three disposable sessions, kept separate from real task observations.
struct StudioMultitaskLightView: View {
    let busy: Bool
    let previewMultitask: () -> Void
    let mockStartedAt: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let states: [(String, Color, String)] = [
        ("进行中", .green, "arrow.triangle.2.circlepath"),
        ("等待处理", .yellow, "hourglass"),
        ("已完成", .red, "checkmark"),
        ("空位", .gray.opacity(0.2), "minus")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("多任务灯效为所有模式共用", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                MultitaskLightCanvas(mockStartedAt: mockStartedAt, animates: !reduceMotion)
                    .frame(height: 20)
                Text(NSLocalizedString("三个会话预览 · 第四段为空位", comment: ""))
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(states.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Circle().fill(states[index].1).frame(width: 8, height: 8)
                        Label(NSLocalizedString(states[index].0, comment: ""), systemImage: states[index].2)
                            .font(.caption)
                        Spacer(minLength: 0)
                    }.padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.025)))
                }
            }
            Text(NSLocalizedString("绿：进行中 · 黄：等待处理 · 红：已完成。颜色随任务状态变化，空位熄灭。", comment: ""))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 12) {
                Text("预览约 10 秒，屏幕会同步展示模拟任务；不会保存或添加真实会话。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: previewMultitask) {
                    Image(systemName: "play.fill").foregroundStyle(.white).padding(8)
                }
                .buttonStyle(.bordered).disabled(busy)
                .help("预览到键盘").accessibilityLabel("预览多任务灯效到键盘")
            }
        }
    }
}
