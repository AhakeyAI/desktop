import SwiftUI
import AhaKeyConfigShared

struct StudioKimiPermissionsView: View {
    var allowsManagement = true
    var showsHeading = true
    var approvalType: UInt8? = nil
    @ObservedObject var model: StudioKimiPermissionsModel
    @State private var pending: StudioKimiPermissionsModel.Candidate?
    @State private var inspection: Task<Void, Never>?
    var pollsStatus = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeading { Text(NSLocalizedString("Kimi 权限", comment: "")).font(.headline) }
            VStack(alignment: .leading, spacing: 10) {
                Text(syncStatus).font(.callout.weight(.semibold))
                Text(NSLocalizedString("Code Desktop 已授权会话跟随拨杆；CLI 默认供重启后新建会话使用，运行中的 TUI 不跟随。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(NSLocalizedString(approvalType == 0 ? "自动档完全自动。" : approvalType == 1 ? "手动档请求批准。" : "自动档完全自动，手动档请求批准。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                if allowsManagement {
                    HStack {
                        Button(NSLocalizedString(model.isBusy ? "核对中…" : "添加会话…", comment: "")) {
                            inspection = Task { await model.inspect() }
                        }.disabled(model.isBusy)
                        Spacer()
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).disabled(model.isBusy)
                            .help(NSLocalizedString("刷新授权记录", comment: ""))
                            .accessibilityLabel(NSLocalizedString("刷新授权记录", comment: ""))
                    }
                }
                ForEach(model.grants, id: \.target) { grant in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(grant.title.isEmpty ? NSLocalizedString("未命名会话", comment: "") : grant.title)
                            Text(NSLocalizedString("已授权", comment: ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if allowsManagement {
                            Button(NSLocalizedString("停止管理", comment: "")) { Task { await model.revoke(grant) } }
                                .disabled(model.isBusy)
                        }
                    }
                }
                if allowsManagement {
                    ForEach(model.candidates.filter { candidate in !model.grants.contains(where: { $0.target == candidate.target }) }) { candidate in
                        HStack {
                            Text(candidate.title.isEmpty ? NSLocalizedString("未命名会话", comment: "") : candidate.title)
                            Spacer()
                            Button(NSLocalizedString("允许拨杆管理…", comment: "")) { pending = candidate }.disabled(model.isBusy)
                        }
                    }
                }
                if model.leases.contains(where: { lease in !model.grants.contains(where: { $0.target == lease.target }) }) {
                    Text(NSLocalizedString("部分原权限仍待后台恢复，请保持 Kimi Code Desktop 开启并刷新记录。", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text(NSLocalizedString("普通 Kimi 暂不支持权限接管。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
        .onAppear { model.refresh() }
        .task(id: pollsStatus) {
            guard pollsStatus else { return }
            while !Task.isCancelled {
                let data = await Task.detached(priority: .utility) {
                    AgentManager.querySocketData(socketPath: "/tmp/ahakey.sock", command: "kimi_desktop_status")
                }.value
                guard !Task.isCancelled else { break }
                model.syncPhase = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["phase"] as? String
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
            }
        }
        .onDisappear {
            inspection?.cancel()
            if pollsStatus { model.cancelInspection() }
        }
        .alert(NSLocalizedString("允许此会话随拨杆切换权限？", comment: ""), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { candidate in
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { pending = nil }
            Button(NSLocalizedString("允许管理", comment: "")) {
                Task { await model.authorize(candidate) }
                pending = nil
            }
        } message: { _ in
            Text(NSLocalizedString("仅管理此会话：自动档完全自动，手动档请求批准；停止接管时恢复原权限并保留已识别的用户修改。允许官方应用加载此会话，正在执行的操作不追溯改变。", comment: ""))
        }
    }

    private var syncStatus: String {
        switch model.syncPhase {
        case "synchronized": return NSLocalizedString("已同步", comment: "")
        case "recovering": return NSLocalizedString("正在恢复原权限", comment: "")
        case "notSynchronized": return NSLocalizedString("尚未同步，以 Kimi 当前权限为准", comment: "")
        case "externalChange": return NSLocalizedString("已保留你修改的权限", comment: "")
        case "noSessions": return NSLocalizedString("尚未添加会话", comment: "")
        default: return NSLocalizedString("等待后台同步状态", comment: "")
        }
    }
}
