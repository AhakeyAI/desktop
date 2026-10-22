import SwiftUI
import AhaKeyConfigShared

struct StudioDeviceInspectorView: View {
    @ObservedObject var model: StudioDeviceInspectorModel
    @ObservedObject var ble: AhaKeyBLEManager
    @ObservedObject var session: StudioInspectorSession
    let lever: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if lever {
                DisclosureGroup(NSLocalizedString("高级动作绑定", comment: ""), isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<2, id: \.self) { index in
                            Text(String(format: NSLocalizedString("位置 %d · 当前：%@", comment: ""), index + 1,
                                positionTitle(model.leverFact.flatMap { $0.value.indices.contains(index) ? $0.value[index] : nil })))
                                .font(.caption).foregroundStyle(.secondary)
                            if let draft = model.leverDraft, draft.positions.count == 2 {
                                SideSwitchPositionEditor(position: Binding(get: {
                                    model.leverDraft?.positions[index] ?? draft.positions[index]
                                }, set: { model.leverDraft?.set($0, at: index) }), title: String(format:
                                    NSLocalizedString("位置 %d", comment: ""), index + 1))
                            }
                        }
                        readButton
                        Text(NSLocalizedString("仅修改拨动时的动作，不切换实体档位。自定义绑定可能关闭自动批准。", comment: ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
            } else {
                Text(NSLocalizedString("待机时间", comment: "")).font(.headline)
                Text(NSLocalizedString("全局设置，应用到所有模式。", comment: "")).font(.caption).foregroundStyle(.secondary)
                if let actual = model.standbyFact?.value {
                    Text(NSLocalizedString("已读取：", comment: "") + standbyTitle(actual)).font(.caption).foregroundStyle(.secondary)
                }
                Picker(NSLocalizedString("待机时间", comment: ""), selection: $model.standbyDraft) {
                    Text(NSLocalizedString("请选择", comment: "")).tag(Optional<UInt16>.none)
                    ForEach([UInt16(0), 30, 60, 120], id: \.self) { value in
                        Text(standbyTitle(value)).tag(Optional(value))
                    }
                }.disabled(model.standbyFact == nil)
                readButton
            }
            if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
            if model.unconfirmed.contains(lever ? .lever : .standby) {
                Text(NSLocalizedString("已发出的修改可能生效，请重新读取后核对。", comment: "")).font(.caption).foregroundStyle(.orange)
            }
        }
        .disabled(model.isBusy || session.isBusy)
        .alert(NSLocalizedString("键盘当前值已变化", comment: ""), isPresented: Binding(get: { model.conflict != nil }, set: { if !$0 { model.conflict = nil } }), presenting: model.conflict) { conflict in
            Button(NSLocalizedString("采用键盘当前值", comment: ""), role: .cancel) { model.adopt(conflict, keepDraft: false) }
            Button(NSLocalizedString("确认修改", comment: "")) {
                model.adopt(conflict, keepDraft: true)
                model.write(lever: lever, ble: ble, session: session)
            }
        } message: { conflict in
            switch conflict.value {
            case .standby(let fact, let desired):
                Text(NSLocalizedString("键盘当前：", comment: "") + standbyTitle(fact.value) + "\n" +
                     NSLocalizedString("待写入：", comment: "") + standbyTitle(desired))
            case .lever(let fact, let desired):
                Text(NSLocalizedString("键盘当前：", comment: "") + fact.value.map { positionTitle($0) }.joined(separator: " / ") + "\n" +
                     NSLocalizedString("待写入：", comment: "") + desired.map { positionTitle($0) }.joined(separator: " / "))
            }
        }
    }
    private var readButton: some View {
        Button(NSLocalizedString("重新读取", comment: "")) { model.read(lever: lever, ble: ble, session: session) }
    }
    private func standbyTitle(_ value: UInt16) -> String {
        value == 0 ? NSLocalizedString("不自动待机", comment: "") : String(format: NSLocalizedString("%d 分钟", comment: ""), Int(value))
    }
    private func positionTitle(_ value: SideSwitchReadback.Position?) -> String {
        guard let value else { return NSLocalizedString("未确认", comment: "") }
        let labels = ["出厂自动", "出厂手动", "禁用", "自定义"]
        guard Int(value.bindType) < labels.count else { return NSLocalizedString("未知绑定", comment: "") }
        return NSLocalizedString(labels[Int(value.bindType)], comment: "")
    }
}
