import Foundation
import Combine
import AhaKeyConfigShared

@MainActor
final class StudioKimiPermissionsModel: ObservableObject {
    struct Candidate: Equatable, Sendable, Identifiable {
        let target: KimiDesktopLeverState.Target
        let title: String
        let serverID: String
        var id: String { target.home + "|" + target.sessionID }
    }
    struct Inspection: Sendable { let sessions: [Candidate]; let limited: Bool }
    struct Access: Sendable {
        var inspect: @Sendable () async throws -> Inspection
        var verify: @Sendable (Candidate) async throws -> Bool
        var notify: @Sendable () async -> Bool
    }
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var grants: [KimiDesktopLeverState.Grant] = []
    @Published private(set) var leases: [KimiDesktopLeverState.Lease] = []
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    private let state: KimiDesktopLeverState
    private let access: Access
    private var revision: UInt64 = 0
    init(state: KimiDesktopLeverState = .init(), access: Access = .production) {
        self.state = state; self.access = access
    }
    func refresh() {
        do {
            let snapshot = try state.snapshot()
            grants = snapshot.grants; leases = snapshot.leases
        } catch { message = NSLocalizedString("无法读取会话授权记录，尚未确认恢复结果。", comment: "") }
    }
    func cancelInspection() { revision &+= 1 }
    func inspect() async {
        guard !isBusy else { return }
        isBusy = true; revision &+= 1
        let ticket = revision
        defer { isBusy = false }
        do {
            let result = try await access.inspect()
            guard !Task.isCancelled, ticket == revision else { return }
            candidates = result.sessions
            message = result.limited
                ? NSLocalizedString("本次只列出部分会话，请稍后重新检测。", comment: "")
                : result.sessions.isEmpty ? NSLocalizedString("未发现可核对的官方 Code Desktop 会话。请先在 Kimi Code Desktop 打开需要管理的会话。", comment: "") : nil
        } catch is CancellationError { }
        catch { if ticket == revision { message = NSLocalizedString("会话检测未完成，未改变任何权限。", comment: "") } }
        refresh()
    }
    func authorize(_ candidate: Candidate) async {
        guard !isBusy, candidates.contains(candidate) else { return }
        isBusy = true; revision &+= 1
        let ticket = revision
        defer { isBusy = false }
        do {
            guard try await access.verify(candidate), !Task.isCancelled, ticket == revision else {
                message = NSLocalizedString("会话连接已变化，请重新检测后授权。", comment: ""); return
            }
            try state.authorize(candidate.target, title: candidate.title, preferredServerID: candidate.serverID)
            let notified = await access.notify()
            message = notified ? NSLocalizedString("已授权，等待后台核对并同步实体拨杆。", comment: "") :
                NSLocalizedString("已保存授权，请启动后台后同步。当前未确认权限已改变。", comment: "")
        } catch { message = NSLocalizedString("未能保存会话授权，请重试；最多同时管理32个会话。", comment: "") }
        refresh()
    }
    func revoke(_ grant: KimiDesktopLeverState.Grant) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try state.revoke(grant.target)
            _ = await access.notify()
            message = NSLocalizedString("已停止接管；后台会核对并恢复原权限，用户后续修改会保留。", comment: "")
        } catch { message = NSLocalizedString("未能停止接管，请重试。", comment: "") }
        refresh()
    }
}

extension StudioKimiPermissionsModel.Access {
    static var production: Self {
        Self(inspect: { try await inspectDesktop() }, verify: { candidate in
            let found = try await inspectDesktop(home: candidate.target.home, serverID: candidate.serverID)
            return found.sessions.contains(candidate)
        }, notify: {
            await Task.detached(priority: .utility) {
                AgentManager.querySocketData(socketPath: "/tmp/ahakey.sock", command: "kimi_desktop_control_changed") != nil
            }.value
        })
    }
    private static func inspectDesktop(home: String? = nil, serverID: String? = nil) async throws -> StudioKimiPermissionsModel.Inspection {
        let homes = home.map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? KimiDesktopInstanceDiscovery.configuredHomes()
        let worker = Task.detached(priority: .utility) { KimiDesktopInstanceDiscovery.scan(homes: homes) }
        let discovery = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        var sessions: [KimiDesktopLeverState.Target: StudioKimiPermissionsModel.Candidate] = [:]
        var ambiguous = Set<KimiDesktopLeverState.Target>(), limited = discovery.limitReached
        var pages = 0
        for instance in discovery.instances where serverID == nil || instance.registration.serverID == serverID {
            let api = KimiDesktopPermissionBridge(instance: instance, authorization: { id, mode in
                id == nil && mode == nil && !Task.isCancelled
            })
            var token: String?, seen = Set<String>()
            repeat {
                try Task.checkCancellation()
                pages += 1
                guard pages <= 512 else { limited = true; break }
                let page = try await api.loadedSessions(pageToken: token)
                for session in page.loadedSessions {
                    let target = try KimiDesktopLeverState.Target(home: instance.homeDirectory.path, sessionID: session.id)
                    let candidate = StudioKimiPermissionsModel.Candidate(target: target, title: session.title, serverID: instance.registration.serverID)
                    if let previous = sessions[target], previous.serverID != candidate.serverID { ambiguous.insert(target) }
                    sessions[target] = candidate
                }
                token = page.nextPageToken
                if let token, !seen.insert(token).inserted { throw KimiDesktopPermissionBridge.Failure.invalidResponse }
            } while token != nil
        }
        for target in ambiguous { sessions.removeValue(forKey: target) }
        return .init(sessions: sessions.values.sorted { $0.id < $1.id }, limited: limited || !ambiguous.isEmpty)
    }
}
