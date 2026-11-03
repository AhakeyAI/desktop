import SwiftUI

/// The firmware renders four task slots with fixed colors, independently of
/// the per-mode single-task effect table. This view never sends preview data.
struct StudioMultitaskLightView: View {
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
                HStack(spacing: 8) {
                    ForEach(states.indices, id: \.self) { index in
                        HStack(spacing: 3) {
                            Capsule().fill(states[index].1)
                            Capsule().fill(states[index].1)
                        }
                    }
                }.frame(height: 12)
                Text(NSLocalizedString("分段示意 · 每段对应一个会话，最多四个", comment: ""))
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
            Text(NSLocalizedString("颜色随任务自动变化，当前固件不支持自定义多任务灯效。", comment: ""))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("在屏幕画面的展示方式中启用多任务，屏幕与灯条会同步切换。", comment: ""))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
