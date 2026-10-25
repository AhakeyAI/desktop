import SwiftUI
import AhaKeyConfigShared

struct StudioRestoreInspectorView: View {
    @ObservedObject var model: StudioRestoreInspectorModel
    let session: StudioInspectorSession
    let access: StudioRestoreInspectorModel.Access
    var body: some View {
        DisclosureGroup(NSLocalizedString("恢复键盘设置", comment: "")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("重置整把键盘的键位、语音路由、待机、拨杆和显示灯光；本地草稿保留。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                if let fact = model.fact {
                    Text(statusTitle(fact.value.state)).font(.callout.weight(.medium))
                    if fact.value.state == .complete {
                        Text(NSLocalizedString("此固件暂不支持再次恢复；分模式语音设置仍可反复修改。", comment: ""))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(NSLocalizedString("核对恢复后的设置", comment: "")) {
                            Task { await model.verify(using: access) }
                        }.disabled(!model.canVerify || session.isBusy)
                    } else if fact.value.canStart {
                        Toggle(NSLocalizedString("本次选择恢复键盘设置", comment: ""), isOn: $model.intendsRestore)
                        if model.intendsRestore {
                            Toggle(NSLocalizedString("已连接键盘 USB 供电，并会保持连接", comment: ""), isOn: $model.usbPowerConfirmed)
                            Text(NSLocalizedString("自定义画面将停止使用；键盘无法导出原素材。仅清除蓝牙配对请使用“忘记主机”，两者不同。", comment: ""))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(NSLocalizedString("准备好后，使用底部“写入键盘”；不会同时保存待机草稿。", comment: ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button(NSLocalizedString(model.isBusy ? "处理中…" : "读取恢复状态", comment: "")) {
                    Task { await model.read(using: access) }
                }.disabled(model.isBusy || session.isBusy)
                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }.padding(.top, 8)
        }
        .disabled(model.isBusy)
    }
    private func statusTitle(_ state: K1RestoreState) -> String {
        let value: String
        switch state {
        case .never: value = "尚未执行恢复"
        case .inProgress: value = "恢复尚在进行，请勿断电"
        case .incomplete: value = "上次恢复未完成"
        case .complete: value = "键盘报告恢复已完成"
        case .storageUnavailable: value = "暂时无法读取恢复记录"
        case .unsupported: value = "此固件不支持恢复初始化"
        }
        return NSLocalizedString(value, comment: "")
    }
}
