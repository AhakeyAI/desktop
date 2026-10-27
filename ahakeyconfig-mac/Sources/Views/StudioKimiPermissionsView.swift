import SwiftUI
import AhaKeyConfigShared

struct StudioKimiPermissionsView: View {
    @StateObject private var model = StudioKimiPermissionsModel()
    @State private var pending: StudioKimiPermissionsModel.Candidate?
    @State private var inspection: Task<Void, Never>?
    var body: some View {
        DisclosureGroup(NSLocalizedString("Kimi Code Desktop 会话权限", comment: "")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("仅管理你授权的会话：自动档为完全自动，手动档请求批准；断连或退出后台时恢复原设置。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(NSLocalizedString(model.isBusy ? "核对中…" : "检测可管理会话", comment: "")) {
                        inspection = Task { await model.inspect() }
                    }.disabled(model.isBusy)
                    Button(NSLocalizedString("刷新接管记录", comment: "")) { model.refresh() }.disabled(model.isBusy)
                }
                ForEach(model.grants, id: \.target) { grant in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(grant.title.isEmpty ? NSLocalizedString("未命名会话", comment: "") : grant.title)
                            Text(NSLocalizedString("已授权，后台按实体拨杆同步", comment: ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(NSLocalizedString("停止管理", comment: "")) { Task { await model.revoke(grant) } }
                            .disabled(model.isBusy)
                    }
                }
                ForEach(model.candidates.filter { candidate in !model.grants.contains(where: { $0.target == candidate.target }) }) { candidate in
                    HStack {
                        Text(candidate.title.isEmpty ? NSLocalizedString("未命名会话", comment: "") : candidate.title)
                        Spacer()
                        Button(NSLocalizedString("允许拨杆管理…", comment: "")) { pending = candidate }.disabled(model.isBusy)
                    }
                }
                if model.leases.contains(where: { lease in !model.grants.contains(where: { $0.target == lease.target }) }) {
                    Text(NSLocalizedString("部分原权限仍待后台恢复，请保持 Kimi Code Desktop 开启并刷新记录。", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text(NSLocalizedString("未授权会话、普通 Kimi 和 CLI TUI 保持原审批流程。已授权的原会话未加载时，允许官方应用重新加载它；正在执行的操作不保证追溯改变。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
        .onAppear { model.refresh() }
        .onDisappear { inspection?.cancel(); model.cancelInspection() }
        .alert(NSLocalizedString("允许此会话随拨杆切换权限？", comment: ""), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { candidate in
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { pending = nil }
            Button(NSLocalizedString("允许管理", comment: "")) {
                Task { await model.authorize(candidate) }
                pending = nil
            }
        } message: { _ in
            Text(NSLocalizedString("自动档将启用完全自动；手动档改为请求批准。退出接管时恢复原权限，并保留之后识别到的用户修改。仅作用于此会话。", comment: ""))
        }
    }
}
