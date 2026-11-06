import SwiftUI
import AhaKeyConfigShared

struct StudioDeviceInspectorView: View {
    @ObservedObject var model: StudioDeviceInspectorModel
    @ObservedObject var ble: AhaKeyBLEManager
    @ObservedObject var session: StudioInspectorSession
    let lever: Bool
    var leverApprovalContent: ((UInt8, Bool) -> AnyView)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if lever {
                HStack {
                    Text(NSLocalizedString("拨动动作", comment: "")).font(.headline)
                    Spacer()
                    Button { model.read(lever: true, ble: ble, session: session) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("重新读取键盘绑定", comment: ""))
                    .accessibilityLabel(NSLocalizedString("重新读取键盘绑定", comment: ""))
                }
                Text(NSLocalizedString("两档独立设置，适用于所有模式。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(0..<2, id: \.self) { index in
                    if index > 0 { Divider().padding(.vertical, 8) }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(NSLocalizedString(index == 0 ? "位置1：拨杆在上" : "位置2：拨杆在下", comment: ""))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let draft = draftPosition(index), draft != factPosition(index) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                    .accessibilityLabel(NSLocalizedString("有未写入的改动", comment: ""))
                            }
                        }
                        if let draft = model.leverDraft, draft.positions.count == 2 {
                            StudioLeverPositionEditor(position: Binding(get: {
                                model.leverDraft?.positions[index] ?? draft.positions[index]
                            }, set: { model.leverDraft?.set($0, at: index) }),
                            positionIndex: index, approvalContent: { kind in
                                let ownsStatusUpdates = model.leverDraft?.positions.firstIndex {
                                    $0.bindType == 0 || $0.bindType == 1
                                } == index
                                return leverApprovalContent?(kind, ownsStatusUpdates) ?? AnyView(EmptyView())
                            })
                        }
                    }
                }
                if let first = model.leverDraft?.positions.first, first.bindType != 0 {
                    Text(NSLocalizedString("写入后将暂停自动批准，拨杆只执行你设置的动作。", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text(NSLocalizedString("待机时间", comment: "")).font(.headline)
                Text(NSLocalizedString("全局设置，应用到所有模式。", comment: "")).font(.caption).foregroundStyle(.secondary)
                Picker(NSLocalizedString("待机时间", comment: ""), selection: $model.standbyDraft) {
                    Text(NSLocalizedString("请选择", comment: "")).tag(Optional<UInt16>.none)
                    ForEach([UInt16(0), 30, 60, 120], id: \.self) { value in
                        Text(standbyTitle(value)).tag(Optional(value))
                    }
                }.disabled(model.standbyFact == nil)
                HStack(spacing: 8) {
                    if let actual = model.standbyFact?.value {
                        Text(NSLocalizedString("已读取当前设置：", comment: "") + standbyTitle(actual))
                    } else {
                        Text(NSLocalizedString("尚未读取当前设置", comment: ""))
                    }
                    if model.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { model.read(lever: false, ble: ble, session: session) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("重新读取", comment: ""))
                        .accessibilityLabel(NSLocalizedString("重新读取", comment: ""))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
    private func draftPosition(_ index: Int) -> SideSwitchReadback.Position? {
        guard let positions = model.leverDraft?.positions, positions.indices.contains(index) else { return nil }
        return positions[index]
    }
    private func factPosition(_ index: Int) -> SideSwitchReadback.Position? {
        guard let positions = model.leverFact?.value, positions.indices.contains(index) else { return nil }
        return positions[index]
    }
    private func standbyTitle(_ value: UInt16) -> String {
        value == 0 ? NSLocalizedString("不自动待机", comment: "") : String(format: NSLocalizedString("%d 分钟", comment: ""), Int(value))
    }
    private func positionTitle(_ value: SideSwitchReadback.Position?) -> String {
        guard let value else { return NSLocalizedString("未确认", comment: "") }
        if value.bindType == 3, let actionType = value.action.first {
            return StudioKeyWriteProposal.actionSummary(.init(mode: 0, keyIndex: 0,
                actionType: actionType, action: Data(value.action.dropFirst(2)), description: Data()))
        }
        let labels = ["出厂自动", "出厂手动", "禁用", "自定义"]
        guard Int(value.bindType) < labels.count else { return NSLocalizedString("未知绑定", comment: "") }
        return NSLocalizedString(labels[Int(value.bindType)], comment: "")
    }
}
