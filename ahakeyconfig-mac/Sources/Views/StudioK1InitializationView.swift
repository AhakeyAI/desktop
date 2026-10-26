import SwiftUI
import AhaKeyConfigShared

struct StudioK1InitializationFact {
    let deviceID: String
    let preparation: K1RouteInitialization.Preparation
}

struct StudioK1InitializationView: View {
    let fact: StudioK1InitializationFact?
    @Binding var selected: Bool
    let busy: Bool
    let modeTitle: (Int) -> String
    let read: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("分模式语音记录暂不可用", comment: "")).font(.callout.weight(.semibold))
            Text(NSLocalizedString("先读取并确认四模式方案，再建立语音路由；不会使用默认键位覆盖未知动作。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            if let fact {
                ForEach(0..<4, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline) {
                        Text(modeTitle(index)).font(.caption.weight(.medium))
                        Spacer()
                        Text(summary(fact, mode: UInt8(index))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(NSLocalizedString("本次初始化四个模式的语音路由", comment: ""), isOn: $selected)
                Text(NSLocalizedString("仅建立读到的方案，不同时保存当前按键草稿。使用底部“写入键盘”确认。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(NSLocalizedString("读取初始化方案", comment: ""), action: read)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .disabled(busy)
    }
    private func summary(_ fact: StudioK1InitializationFact, mode: UInt8) -> String {
        if fact.preparation.inputs.voiceState == 2 { return NSLocalizedString("系统听写（Consumer）", comment: "") }
        guard let key = fact.preparation.inputs.keys.first(where: { $0.mode == mode }) else {
            return NSLocalizedString("未确认", comment: "")
        }
        return StudioKeyWriteProposal.actionSummary(key)
    }
}
