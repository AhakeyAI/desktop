import Combine
import Foundation
import AhaKeyConfigShared

/// 一次点击冻结的提交输入。
///
/// 卡片 C5G 要求：`deviceID + session/transport generation + page/profile + selected set +
/// fields/baselines + explicit intent` 每次点击只冻结一次，identity、overwrite decision、
/// attempt token、Facade snapshot 与 result consumption 必须全部由同一份 frozen input 派生。
/// 本类型就是那份冻结值；`start` 内部不再读取任何 live computed property。
struct AhaKeyStudioPageSubmissionInput: Equatable, Sendable {
    var deviceID: AhaKeyRuntimeDeviceID
    var sessionGeneration: AhaKeyRuntimeSessionGeneration
    var transportGeneration: AhaKeyRuntimeTransportGeneration
    /// 冻结页快照。`overwriteConfirmed` 由 coordinator 决定，调用方必须传 false。
    var snapshot: AhaKeyStudioPageSnapshot
    var explicitIntentFieldIDs: Set<AhaKeyStudioFieldID>
    var retryResidual: Bool

    var pageID: AhaKeyStudioPageID { snapshot.pageID }

    /// 由同一份冻结快照派生 identity，避免一次点击产生两个不同快照。
    var confirmationIdentity: AhaKeyStudioPageOverwriteConfirmationIdentity {
        AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: deviceID,
            sessionGeneration: sessionGeneration,
            transportGeneration: transportGeneration,
            snapshot: snapshot
        )
    }

    func frozenSnapshot(overwriteConfirmed: Bool) -> AhaKeyStudioPageSnapshot {
        var next = snapshot
        next.overwriteConfirmed = overwriteConfirmed
        return next
    }
}

/// 显式编辑意图的观测上下文。由 View 提供（coordinator 不读 draft/Store）。
struct AhaKeyStudioPageEditIntentContext: Equatable, Sendable {
    var deviceID: AhaKeyRuntimeDeviceID?
    var sessionGeneration: AhaKeyRuntimeSessionGeneration
    var transportGeneration: AhaKeyRuntimeTransportGeneration
    var pageID: AhaKeyStudioPageID
    var profile: AhaKeyOLEDCompatibilityProfile
    var currentValues: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue]
}

/// 提交端口。生产 adapter 走 `AhaKeyStudioRuntimeClient.commitFrozenPage`；
/// 测试 adapter 记录每次 snapshot/result，不触碰真机。
@MainActor
protocol AhaKeyStudioPageCommitPort {
    func commitFrozenPage(
        _ snapshot: AhaKeyStudioPageSnapshot,
        retryResidual: Bool
    ) async throws -> AhaKeyStudioPageCommitResult
}

/// 生产 adapter：唯一副作用是已验收的 Store 写入口。
///
/// **不强持有 client**：否则会形成 `client → registry → execution → port → client` 闭环，
/// 永久挂起的 port 会把整条图钉住。持有方释放后按 fail-closed 报 runtimeOffline。
@MainActor
struct AhaKeyStudioRuntimeStoreCommitPort: AhaKeyStudioPageCommitPort {
    weak var store: AhaKeyStudioRuntimeClient?

    init(store: AhaKeyStudioRuntimeClient) {
        self.store = store
    }

    func commitFrozenPage(
        _ snapshot: AhaKeyStudioPageSnapshot,
        retryResidual: Bool
    ) async throws -> AhaKeyStudioPageCommitResult {
        guard let store else { throw AhaKeyStudioStoreApplyError.runtimeOffline }
        return try await store.commitFrozenPage(snapshot, retryResidual: retryResidual)
    }
}

// MARK: - Trace

enum AhaKeyStudioPageCommitTracePhase: String, Equatable, Sendable {
    /// Button 同步进入 attempt；port 尚未调用。
    case began
    /// 内部 Task 通过 pre-port fence 并实际进入 port 调用。
    case portInvoked
    case returned
    case failed
    /// live identity 变化导致结果被丢弃（**不含**用户取消）。
    case superseded
    /// 已有在途租约或 frozen/live 不一致，未进入 attempt。
    case rejected
    /// 收到用户取消请求（port 可能在飞行中）。
    case cancelRequested
    /// 被取消的 attempt 已结算（租约释放）；`discarded` 说明结果是否被丢弃。
    case cancelSettled
}

/// `.returned` 专用结果类型：只允许真实 commit 返回值。
/// `pending` / `failed` / `superseded` / `rejected` / `cancelled` 在**编译类型上不可构造**。
enum AhaKeyStudioPageCommitReturnedResult: String, Equatable, Sendable {
    case accepted
    case noOp
    case requiresOverwriteConfirmation
    case missingTrustedPageCache
    case unsupportedProfile
    case unsupportedPage

    /// 精确映射：`AhaKeyStudioPageCommitResult` 恰有这 6 个 case，无兜底、无降级。
    init(_ result: AhaKeyStudioPageCommitResult) {
        switch result {
        case .noOp: self = .noOp
        case .requiresOverwriteConfirmation: self = .requiresOverwriteConfirmation
        case .missingTrustedPageCache: self = .missingTrustedPageCache
        case .unsupportedProfile: self = .unsupportedProfile
        case .unsupportedPage: self = .unsupportedPage
        case .accepted: self = .accepted
        }
    }

    var category: AhaKeyStudioPageCommitTraceCategory {
        switch self {
        case .accepted: return .accepted
        case .noOp: return .noOp
        case .requiresOverwriteConfirmation: return .requiresOverwriteConfirmation
        case .missingTrustedPageCache: return .missingTrustedPageCache
        case .unsupportedProfile: return .unsupportedProfile
        case .unsupportedPage: return .unsupportedPage
        }
    }
}

enum AhaKeyStudioPageCommitTraceCategory: String, Equatable, Sendable {
    /// attempt 已开始，尚无结果。
    case pending
    case accepted
    case noOp
    case requiresOverwriteConfirmation
    case missingTrustedPageCache
    case unsupportedProfile
    case unsupportedPage
    case failed
    /// live identity 变化，旧结果不得投影。
    case superseded
    /// 已有在途租约 / frozen 与 live 不一致，未产生 port 调用。
    case inFlightRejected
    /// 用户取消请求。
    case cancelRequested
    /// 用户取消结算。
    case cancelSettled
}

/// 结构化 trace 事件：`phase` / `portInvoked` / `category` / `confirmed` 全部由 case 派生，
/// 矛盾的字段组合在产品类型层**不可构造**。用户取消与 identity 变化是**不同类型**。
enum AhaKeyStudioPageCommitTraceEvent: Equatable, Sendable {
    case began(sequence: UInt64, pageID: AhaKeyStudioPageID, confirmed: Bool)
    case portInvoked(sequence: UInt64, pageID: AhaKeyStudioPageID, confirmed: Bool)
    case returned(
        sequence: UInt64,
        pageID: AhaKeyStudioPageID,
        confirmed: Bool,
        result: AhaKeyStudioPageCommitReturnedResult
    )
    case failed(sequence: UInt64, pageID: AhaKeyStudioPageID, confirmed: Bool)
    case superseded(
        sequence: UInt64,
        pageID: AhaKeyStudioPageID,
        confirmed: Bool,
        portInvoked: Bool
    )
    case rejected(sequence: UInt64, pageID: AhaKeyStudioPageID)
    case cancelRequested(
        sequence: UInt64,
        pageID: AhaKeyStudioPageID,
        confirmed: Bool,
        portInvoked: Bool
    )
    /// `discardedResult`：被取消的 attempt 的旧 port 结果是否被丢弃（`portInvoked=true` 时才有意义）。
    case cancelSettled(
        sequence: UInt64,
        pageID: AhaKeyStudioPageID,
        confirmed: Bool,
        portInvoked: Bool
    )

    var sequence: UInt64 {
        switch self {
        case .began(let sequence, _, _),
             .portInvoked(let sequence, _, _),
             .returned(let sequence, _, _, _),
             .failed(let sequence, _, _),
             .superseded(let sequence, _, _, _),
             .rejected(let sequence, _),
             .cancelRequested(let sequence, _, _, _),
             .cancelSettled(let sequence, _, _, _):
            return sequence
        }
    }

    var pageID: AhaKeyStudioPageID {
        switch self {
        case .began(_, let pageID, _),
             .portInvoked(_, let pageID, _),
             .returned(_, let pageID, _, _),
             .failed(_, let pageID, _),
             .superseded(_, let pageID, _, _),
             .rejected(_, let pageID),
             .cancelRequested(_, let pageID, _, _),
             .cancelSettled(_, let pageID, _, _):
            return pageID
        }
    }

    var phase: AhaKeyStudioPageCommitTracePhase {
        switch self {
        case .began: return .began
        case .portInvoked: return .portInvoked
        case .returned: return .returned
        case .failed: return .failed
        case .superseded: return .superseded
        case .rejected: return .rejected
        case .cancelRequested: return .cancelRequested
        case .cancelSettled: return .cancelSettled
        }
    }

    /// 该事件发生时 port 是否已被调用。
    var portInvoked: Bool {
        switch self {
        case .began, .rejected: return false
        case .portInvoked, .returned, .failed: return true
        case .superseded(_, _, _, let portInvoked): return portInvoked
        case .cancelRequested(_, _, _, let portInvoked): return portInvoked
        case .cancelSettled(_, _, _, let portInvoked): return portInvoked
        }
    }

    var category: AhaKeyStudioPageCommitTraceCategory {
        switch self {
        case .began, .portInvoked: return .pending
        case .returned(_, _, _, let result): return result.category
        case .failed: return .failed
        case .superseded: return .superseded
        case .rejected: return .inFlightRejected
        case .cancelRequested: return .cancelRequested
        case .cancelSettled: return .cancelSettled
        }
    }

    /// `.rejected` 未进入 attempt，因此没有覆盖确认决策。
    var confirmed: Bool {
        switch self {
        case .began(_, _, let confirmed),
             .portInvoked(_, _, let confirmed),
             .returned(_, _, let confirmed, _),
             .failed(_, _, let confirmed),
             .superseded(_, _, let confirmed, _),
             .cancelRequested(_, _, let confirmed, _),
             .cancelSettled(_, _, let confirmed, _):
            return confirmed
        case .rejected:
            return false
        }
    }

    /// 供证据 / HIL 读取的稳定文本行（无敏感内容）。
    var evidenceLine: String {
        "seq=\(sequence) phase=\(phase.rawValue)"
            + " page=\(AhaKeyStudioPageChromeProjector.pageTitle(pageID))"
            + " confirmed=\(confirmed) portInvoked=\(portInvoked) category=\(category.rawValue)"
    }
}

// MARK: - Outcome / projection

/// 一次 submit 的结果投影。UI 文案与 chrome 全部由它派生，保证 no-op/requires/error 可区分。
enum AhaKeyStudioPageCommitOutcome: Equatable, Sendable {
    case noOp
    case requiresOverwriteConfirmation
    case missingTrustedPageCache
    case unsupportedProfile
    case unsupportedPage
    case accepted(AhaKeyRuntimeOperationID)
    case failed(String)
    /// live context 在 await 中变化：旧结果不得作为当前页面结果投影。
    case superseded
    /// 单次在途保护或 frozen/live 不一致：本次点击未产生 port 调用。
    case ignoredInFlight
    /// 用户取消 / 对象释放：在途 attempt 被取消。
    case cancelled

    init(_ result: AhaKeyStudioPageCommitResult) {
        switch result {
        case .noOp: self = .noOp
        case .requiresOverwriteConfirmation: self = .requiresOverwriteConfirmation
        case .missingTrustedPageCache: self = .missingTrustedPageCache
        case .unsupportedProfile: self = .unsupportedProfile
        case .unsupportedPage: self = .unsupportedPage
        case .accepted(let id): self = .accepted(id)
        }
    }

    /// 是否允许写入 `lastOutcome` 并投影给 UI。失效结果一律不得进入。
    var isProjectable: Bool {
        switch self {
        case .superseded, .ignoredInFlight, .cancelled: return false
        case .noOp, .requiresOverwriteConfirmation, .missingTrustedPageCache,
             .unsupportedProfile, .unsupportedPage, .accepted, .failed:
            return true
        }
    }
}

/// 一次提交的投影。**携带冻结 pageID**：View 不得改用 live `currentPageID`/`currentPageChrome`
/// 展示结果，否则页面在 await 中切换后旧结果会被挂到新页面上。
struct AhaKeyStudioPageCommitProjection: Equatable, Sendable {
    var pageID: AhaKeyStudioPageID
    var outcome: AhaKeyStudioPageCommitOutcome
}

/// `start(_:port:)` 的同步返回值。**不含 `Task`**：异步生命周期归执行租约注册表所有。
enum AhaKeyStudioPageCommitStartResult: Equatable {
    /// attempt 已在同步阶段开始；终结结果经 `lastProjection` / `projectionRevision` 发布。
    case started
    /// 未进入 attempt（已有在途租约，或 frozen 与 live identity 不一致），已带终态投影。
    case rejected(AhaKeyStudioPageCommitProjection)
}

// MARK: - Owner capability

/// Coordinator 的 owner capability。注册表只认 capability，不认「最后一个 attach 的人」。
struct AhaKeyStudioPageCommitOwnerCapability: Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

// MARK: - Per-attempt execution record

/// 单个 attempt 的执行租约。所有可变状态都是 per-attempt 的，
/// 旧 Task 不可能改写新 attempt 的状态。
@MainActor
final class AhaKeyStudioPageCommitExecution {
    /// 发起并独占该 attempt 的 capability。只有它能取消/结算本 attempt。
    let ownerCapability: AhaKeyStudioPageCommitOwnerCapability
    /// 发起该 attempt 的 coordinator。**weak**：origin 释放后结果只做 cleanup，不交给无关 successor。
    weak var originator: (any AhaKeyStudioPageCommitExecutionDelegate)?
    let attempt: AhaKeyStudioPageOverwriteConfirmationAttemptToken
    let identity: AhaKeyStudioPageOverwriteConfirmationIdentity
    let revisionAtSubmit: UInt64
    let sequence: UInt64
    let pageID: AhaKeyStudioPageID
    let confirmed: Bool
    let snapshot: AhaKeyStudioPageSnapshot
    let retryResidual: Bool
    let port: any AhaKeyStudioPageCommitPort

    private(set) var portInvoked = false
    private(set) var cancelRequested = false

    init(
        ownerCapability: AhaKeyStudioPageCommitOwnerCapability,
        originator: any AhaKeyStudioPageCommitExecutionDelegate,
        attempt: AhaKeyStudioPageOverwriteConfirmationAttemptToken,
        identity: AhaKeyStudioPageOverwriteConfirmationIdentity,
        revisionAtSubmit: UInt64,
        sequence: UInt64,
        pageID: AhaKeyStudioPageID,
        confirmed: Bool,
        snapshot: AhaKeyStudioPageSnapshot,
        retryResidual: Bool,
        port: any AhaKeyStudioPageCommitPort
    ) {
        self.ownerCapability = ownerCapability
        self.originator = originator
        self.attempt = attempt
        self.identity = identity
        self.revisionAtSubmit = revisionAtSubmit
        self.sequence = sequence
        self.pageID = pageID
        self.confirmed = confirmed
        self.snapshot = snapshot
        self.retryResidual = retryResidual
        self.port = port
    }

    func markPortInvoked() { portInvoked = true }
    func requestCancel() { cancelRequested = true }
}

// MARK: - Execution lease registry

/// 执行租约的回调接收方。coordinator 实现它；租约本身由注册表拥有。
@MainActor
protocol AhaKeyStudioPageCommitExecutionDelegate: AnyObject {
    /// port 正常返回且未被丢弃：由 originating coordinator 消费 ledger 并投影。
    func executionDidComplete(
        _ execution: AhaKeyStudioPageCommitExecution,
        portResult: Result<AhaKeyStudioPageCommitResult, Error>
    )
    /// 结果被丢弃（identity 变化 / 用户取消）：**不消费 ledger、不写 lastOutcome**。
    func executionDidDiscard(
        _ execution: AhaKeyStudioPageCommitExecution,
        outcome: AhaKeyStudioPageCommitOutcome
    )
    /// 占用变化：当前活跃 coordinator 刷新 `isSubmitting`。
    func executionOccupancyDidChange()
}

/// **app-lifetime** 的 port 执行租约注册表。
///
/// 由 `AhaKeyStudioRuntimeClient` 持有并注入 coordinator（不是 static global，随 Store 生命周期）。
///
/// 多窗口 / 迟到的 handoff 规则：
/// - `observeIdentity` / `start` 只允许 **active capability** 操作自己；
/// - `requestCancel` / `settleCancelBeforePort` 只允许 **lease 的 owner capability**；
///   继任 coordinator 可以观察 inherited occupancy，但**不得取消或 supersede** 它；
/// - completion 路由给 execution 冻结的 originating weak delegate；origin 已释放则只做 cleanup。
@MainActor
final class AhaKeyStudioPageCommitExecutionRegistry {
    static let traceCapacity = 64

    private struct Observation {
        var identity: AhaKeyStudioPageOverwriteConfirmationIdentity?
        var revision: UInt64
    }

    private(set) var lease: AhaKeyStudioPageCommitExecution?
    private(set) var attemptSequence: UInt64 = 0
    private(set) var clickCount: UInt64 = 0
    private(set) var portCallCount: UInt64 = 0
    /// 仅统计 **identity 变化**导致的丢弃。
    private(set) var supersededCount: UInt64 = 0
    /// 仅统计 **用户取消请求**次数（每次取消恰一次，重复请求幂等）。
    private(set) var cancelRequestedCount: UInt64 = 0
    private(set) var trace: [AhaKeyStudioPageCommitTraceEvent] = []

    private(set) var activeCapability: AhaKeyStudioPageCommitOwnerCapability?
    private var observations: [AhaKeyStudioPageCommitOwnerCapability: Observation] = [:]
    private var revisionCounter: UInt64 = 0
    private var task: Task<Void, Never>?
    private weak var activeOccupancyObserver: (any AhaKeyStudioPageCommitExecutionDelegate)?
    private var traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?

    var isOccupied: Bool { lease != nil }

    // MARK: Capability

    /// 注册一个 owner capability 并使其成为活跃观察者。不得退回 static global。
    func activate(
        capability: AhaKeyStudioPageCommitOwnerCapability,
        delegate: any AhaKeyStudioPageCommitExecutionDelegate
    ) {
        activeCapability = capability
        activeOccupancyObserver = delegate
        if observations[capability] == nil {
            revisionCounter = Self.checkedIncrement(revisionCounter)
            observations[capability] = Observation(identity: nil, revision: revisionCounter)
        }
        delegate.executionOccupancyDidChange()
    }

    func deactivate(capability: AhaKeyStudioPageCommitOwnerCapability) {
        guard activeCapability == capability else { return }
        activeCapability = nil
        activeOccupancyObserver = nil
    }

    func observation(
        for capability: AhaKeyStudioPageCommitOwnerCapability
    ) -> (identity: AhaKeyStudioPageOverwriteConfirmationIdentity?, revision: UInt64) {
        let observation = observations[capability]
            ?? Observation(identity: nil, revision: 0)
        return (observation.identity, observation.revision)
    }

    /// 只有 active capability 能推进自己的 observation。
    func observeIdentity(
        _ identity: AhaKeyStudioPageOverwriteConfirmationIdentity?,
        by capability: AhaKeyStudioPageCommitOwnerCapability
    ) {
        guard activeCapability == capability else { return }
        var observation: Observation
        if let existing = observations[capability] {
            observation = existing
        } else {
            revisionCounter = Self.checkedIncrement(revisionCounter)
            observation = Observation(identity: nil, revision: revisionCounter)
        }
        if observation.identity != identity {
            revisionCounter = Self.checkedIncrement(revisionCounter)
            observation.revision = revisionCounter
        }
        observation.identity = identity
        observations[capability] = observation
    }

    // MARK: Lease

    /// 占用租约。只允许 active capability，且必须租约为空。
    @discardableResult
    func claim(
        _ execution: AhaKeyStudioPageCommitExecution,
        by capability: AhaKeyStudioPageCommitOwnerCapability
    ) -> Bool {
        guard activeCapability == capability else { return false }
        guard lease == nil else { return false }
        lease = execution
        record(.began(
            sequence: execution.sequence,
            pageID: execution.pageID,
            confirmed: execution.confirmed
        ))
        startPortTask(execution)
        activeOccupancyObserver?.executionOccupancyDidChange()
        return true
    }

    /// 请求取消。**幂等**：已 requested 时 no-op（不重复计数、不重复 trace）；
    /// 非 lease owner 一律 no-op。
    @discardableResult
    func requestCancel(
        by capability: AhaKeyStudioPageCommitOwnerCapability
    ) -> AhaKeyStudioPageCommitExecution? {
        guard let lease, lease.ownerCapability == capability else { return nil }
        guard !lease.cancelRequested else { return nil }
        lease.requestCancel()
        cancelRequestedCount = Self.checkedIncrement(cancelRequestedCount)
        record(.cancelRequested(
            sequence: lease.sequence,
            pageID: lease.pageID,
            confirmed: lease.confirmed,
            portInvoked: lease.portInvoked
        ))
        return lease
    }

    /// cancel-before-port：fence 保证旧 Task 永不调用 port，可安全立即释放租约并结算。
    /// 只有 lease owner 能结算；重复调用因租约已释放而 no-op。
    func settleCancelBeforePort(
        _ execution: AhaKeyStudioPageCommitExecution,
        by capability: AhaKeyStudioPageCommitOwnerCapability
    ) {
        guard lease === execution, execution.ownerCapability == capability else { return }
        record(.cancelSettled(
            sequence: execution.sequence,
            pageID: execution.pageID,
            confirmed: execution.confirmed,
            portInvoked: false
        ))
        let originator = execution.originator
        release(execution)
        originator?.executionDidDiscard(execution, outcome: .cancelled)
    }

    /// 显式关闭契约：fence 新请求、放弃在途租约、取消 port Task。
    /// 供 client/registry 在释放或停机时收口，保证 hung port 不永久保留占用。
    func shutdown() {
        task?.cancel()
        task = nil
        if let lease {
            record(.cancelSettled(
                sequence: lease.sequence,
                pageID: lease.pageID,
                confirmed: lease.confirmed,
                portInvoked: lease.portInvoked
            ))
            self.lease = nil
        }
        activeCapability = nil
        activeOccupancyObserver?.executionOccupancyDidChange()
        activeOccupancyObserver = nil
        observations.removeAll()
    }

    func noteIdentitySuperseded() {
        supersededCount = Self.checkedIncrement(supersededCount)
    }

    func bumpAttemptSequence() -> UInt64 {
        attemptSequence = Self.checkedIncrement(attemptSequence)
        return attemptSequence
    }

    func bumpClickCount() {
        clickCount = Self.checkedIncrement(clickCount)
    }

    func setTraceSink(_ sink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?) {
        traceSink = sink
    }

    func record(_ event: AhaKeyStudioPageCommitTraceEvent) {
        trace.append(event)
        if trace.count > Self.traceCapacity {
            trace.removeFirst(trace.count - Self.traceCapacity)
        }
        traceSink?(event)
    }

    // MARK: Private pipeline

    private func release(_ execution: AhaKeyStudioPageCommitExecution) {
        guard lease === execution else { return }
        lease = nil
        task = nil
        activeOccupancyObserver?.executionOccupancyDidChange()
    }

    private func startPortTask(_ execution: AhaKeyStudioPageCommitExecution) {
        // port 调用段不捕获注册表强引用：await 期间只持有 execution 与 port，避免保留环。
        task = Task { @MainActor [weak self] in
            guard let admitted = self?.admitPortEntry(execution), admitted else { return }
            let portResult: Result<AhaKeyStudioPageCommitResult, Error>
            do {
                portResult = .success(try await execution.port.commitFrozenPage(
                    execution.snapshot,
                    retryResidual: execution.retryResidual
                ))
            } catch {
                portResult = .failure(error)
            }
            self?.settle(execution, portResult: portResult)
        }
    }

    /// 第二次 pre-port fence：在任何计数 / trace / port 调用之前核 Task cancellation、
    /// exact lease、**该 attempt owner 的** observation 与 live identity。
    /// 继任 coordinator 的 observation 不会影响 inherited execution。
    private func admitPortEntry(_ execution: AhaKeyStudioPageCommitExecution) -> Bool {
        guard lease === execution else { return false }

        guard !Task.isCancelled,
              !execution.cancelRequested,
              !isOwnerObservationStale(execution)
        else {
            let cancelled = execution.cancelRequested || Task.isCancelled
            if !cancelled {
                noteIdentitySuperseded()
            }
            settleDiscarded(
                execution,
                portInvoked: false,
                outcome: cancelled ? .cancelled : .superseded,
                isCancel: cancelled
            )
            return false
        }

        execution.markPortInvoked()
        portCallCount = Self.checkedIncrement(portCallCount)
        record(.portInvoked(
            sequence: execution.sequence,
            pageID: execution.pageID,
            confirmed: execution.confirmed
        ))
        return true
    }

    private func isOwnerObservationStale(_ execution: AhaKeyStudioPageCommitExecution) -> Bool {
        guard let observation = observations[execution.ownerCapability] else { return true }
        return observation.revision != execution.revisionAtSubmit
            || observation.identity != execution.identity
    }

    private func settle(
        _ execution: AhaKeyStudioPageCommitExecution,
        portResult: Result<AhaKeyStudioPageCommitResult, Error>
    ) {
        guard lease === execution else { return }

        if execution.cancelRequested || Task.isCancelled {
            settleDiscarded(
                execution,
                portInvoked: execution.portInvoked,
                outcome: .cancelled,
                isCancel: true
            )
            return
        }

        if isOwnerObservationStale(execution) {
            noteIdentitySuperseded()
            settleDiscarded(
                execution,
                portInvoked: execution.portInvoked,
                outcome: .superseded,
                isCancel: false
            )
            return
        }

        switch portResult {
        case .success(let result):
            record(.returned(
                sequence: execution.sequence,
                pageID: execution.pageID,
                confirmed: execution.confirmed,
                result: AhaKeyStudioPageCommitReturnedResult(result)
            ))
        case .failure:
            record(.failed(
                sequence: execution.sequence,
                pageID: execution.pageID,
                confirmed: execution.confirmed
            ))
        }

        let originator = execution.originator
        release(execution)
        // origin 已释放则只做 cleanup：结果不交给无关 successor。
        originator?.executionDidComplete(execution, portResult: portResult)
    }

    private func settleDiscarded(
        _ execution: AhaKeyStudioPageCommitExecution,
        portInvoked: Bool,
        outcome: AhaKeyStudioPageCommitOutcome,
        isCancel: Bool
    ) {
        guard lease === execution else { return }
        if isCancel {
            record(.cancelSettled(
                sequence: execution.sequence,
                pageID: execution.pageID,
                confirmed: execution.confirmed,
                portInvoked: portInvoked
            ))
        } else {
            record(.superseded(
                sequence: execution.sequence,
                pageID: execution.pageID,
                confirmed: execution.confirmed,
                portInvoked: portInvoked
            ))
        }
        let originator = execution.originator
        release(execution)
        originator?.executionDidDiscard(execution, outcome: outcome)
    }

    /// checked fail-closed increment：溢出是程序性错误，直接 trap，绝不回绕。
    static func checkedIncrement(_ value: UInt64) -> UInt64 {
        value + 1
    }
}

// MARK: - Coordinator

/// 两击提交的唯一可观测编排（C5G → C5GR5）。
///
/// View 只调用同步 `start(_:port:)`。**执行租约由 app-lifetime 注册表拥有**，
/// coordinator 只负责自己 session 的 ledger、chrome 投影与结果发布。
@MainActor
final class AhaKeyStudioPageCommitCoordinator: ObservableObject {
    @Published private(set) var pendingPrompt: AhaKeyStudioPageOverwriteConfirmationIdentity?
    @Published private(set) var isSubmitting = false
    @Published private(set) var lastOutcome: AhaKeyStudioPageCommitOutcome?
    /// 最近一次终结投影事件。View 经 `onChange(of: projectionRevision)` 消费。
    @Published private(set) var lastProjection: AhaKeyStudioPageCommitProjection?
    /// 每次发布终结投影时 checked 递增；单调值使重复同值投影也能被 View 观察到。
    @Published private(set) var projectionRevision: UInt64 = 0

    private let registry: AhaKeyStudioPageCommitExecutionRegistry
    let capability: AhaKeyStudioPageCommitOwnerCapability
    private var confirmationLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
    private var editIntentLedger = AhaKeyStudioPageEditIntentLedger()

    init(registry: AhaKeyStudioPageCommitExecutionRegistry) {
        self.registry = registry
        self.capability = AhaKeyStudioPageCommitOwnerCapability()
        registry.activate(capability: capability, delegate: self)
    }

    /// 页面关闭：交还 active 观察权。迟到的调用不会影响其他 owner
    /// （`requestCancel`/`observeIdentity` 都按 capability 校验）。
    func detach() {
        registry.deactivate(capability: capability)
    }

    // 观测口径转发到 app-lifetime 注册表，保证 successor coordinator 看到同一份事实。
    var currentIdentity: AhaKeyStudioPageOverwriteConfirmationIdentity? {
        registry.observation(for: capability).identity
    }
    var observationRevision: UInt64 { registry.observation(for: capability).revision }
    var attemptSequence: UInt64 { registry.attemptSequence }
    var clickCount: UInt64 { registry.clickCount }
    var portCallCount: UInt64 { registry.portCallCount }
    var supersededCount: UInt64 { registry.supersededCount }
    var cancelRequestedCount: UInt64 { registry.cancelRequestedCount }
    var trace: [AhaKeyStudioPageCommitTraceEvent] { registry.trace }
    var inFlight: AhaKeyStudioPageCommitExecution? { registry.lease }
    /// successor 可观察 inherited occupancy，但无权取消或 supersede 它。
    var hasInheritedExecution: Bool {
        guard let lease = registry.lease else { return false }
        return lease.ownerCapability != capability
    }

    /// 生产写入 Studio 现有 comm log；测试不设置 sink，只读 `trace`。
    func setTraceSink(_ sink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?) {
        registry.setTraceSink(sink)
    }

    // MARK: - Observation（View 驱动；Button click path 禁止调用）

    /// View 发布 live identity。只允许 active capability 推进。
    func observeIdentity(_ identity: AhaKeyStudioPageOverwriteConfirmationIdentity?) {
        registry.observeIdentity(identity, by: capability)
        confirmationLedger.observeCurrentIdentity(identity)
        let pending = confirmationLedger.pending
        if pendingPrompt != pending {
            pendingPrompt = pending
        }
    }

    func observeExplicitIntentContext(_ context: AhaKeyStudioPageEditIntentContext) {
        editIntentLedger.observeContext(
            deviceID: context.deviceID,
            sessionGeneration: context.sessionGeneration,
            transportGeneration: context.transportGeneration,
            pageID: context.pageID,
            profile: context.profile,
            currentValues: context.currentValues
        )
    }

    /// 套图 Picker setter 是唯一登记 `.screenActiveSet` 的入口。
    func notePickerSelection(
        activeSet: Int,
        modeSlot: UInt8,
        deviceID: AhaKeyRuntimeDeviceID,
        sessionGeneration: AhaKeyRuntimeSessionGeneration,
        transportGeneration: AhaKeyRuntimeTransportGeneration,
        profile: AhaKeyOLEDCompatibilityProfile
    ) {
        editIntentLedger.notePickerSelection(
            activeSet: activeSet,
            modeSlot: modeSlot,
            deviceID: deviceID,
            sessionGeneration: sessionGeneration,
            transportGeneration: transportGeneration,
            profile: profile
        )
    }

    func matchingExplicitIntentFieldIDs(
        _ context: AhaKeyStudioPageEditIntentContext
    ) -> Set<AhaKeyStudioFieldID> {
        guard let deviceID = context.deviceID else { return [] }
        return editIntentLedger.matchingFieldIDs(
            deviceID: deviceID,
            sessionGeneration: context.sessionGeneration,
            transportGeneration: context.transportGeneration,
            pageID: context.pageID,
            profile: context.profile,
            currentValues: context.currentValues
        )
    }

    func applyingPendingPrompt(
        to chrome: AhaKeyStudioPageChrome,
        for identity: AhaKeyStudioPageOverwriteConfirmationIdentity?
    ) -> AhaKeyStudioPageChrome {
        confirmationLedger.applyingPendingPrompt(to: chrome, for: identity)
    }

    // MARK: - Submit

    /// 唯一提交入口（同步）。只允许 active capability。
    func start(
        _ input: AhaKeyStudioPageSubmissionInput,
        port: any AhaKeyStudioPageCommitPort
    ) -> AhaKeyStudioPageCommitStartResult {
        registry.bumpClickCount()

        // 非 active owner（迟到 / 已 detach）不得发起。
        guard registry.activeCapability == capability else {
            let projection = AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .ignoredInFlight
            )
            publish(projection)
            return .rejected(projection)
        }

        // 任一 successor coordinator 都会看到旧 invoked 租约并在此拒绝。
        guard !registry.isOccupied else {
            registry.record(.rejected(sequence: registry.attemptSequence, pageID: input.pageID))
            let projection = AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .ignoredInFlight
            )
            publish(projection)
            return .rejected(projection)
        }

        let identity = input.confirmationIdentity
        let observation = registry.observation(for: capability)

        // 第一次 pre-port 一致性验证：冻结 input 必须等于本 session 已观测的 live identity。
        guard observation.identity == identity else {
            registry.noteIdentitySuperseded()
            registry.record(.superseded(
                sequence: registry.attemptSequence,
                pageID: input.pageID,
                confirmed: false,
                portInvoked: false
            ))
            let projection = AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .superseded
            )
            publish(projection)
            return .rejected(projection)
        }

        let confirmed = confirmationLedger.shouldSubmitConfirmed(for: identity)
        let attempt = confirmationLedger.beginAttempt(for: identity)
        editIntentLedger.bindAttempt(attempt, fields: input.explicitIntentFieldIDs)

        let execution = AhaKeyStudioPageCommitExecution(
            ownerCapability: capability,
            originator: self,
            attempt: attempt,
            identity: identity,
            revisionAtSubmit: observation.revision,
            sequence: registry.bumpAttemptSequence(),
            pageID: input.pageID,
            confirmed: confirmed,
            snapshot: input.frozenSnapshot(overwriteConfirmed: confirmed),
            retryResidual: input.retryResidual,
            port: port
        )
        guard registry.claim(execution, by: capability) else {
            let projection = AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .ignoredInFlight
            )
            publish(projection)
            return .rejected(projection)
        }
        refreshSubmitting()
        return .started
    }

    /// 页面关闭 / 显式取消。只有 lease owner 能取消自己的 attempt；
    /// 继任 coordinator 调用它不会影响 inherited execution。
    func cancelInFlight() {
        guard let execution = registry.requestCancel(by: capability) else {
            refreshSubmitting()
            return
        }
        refreshSubmitting()
        guard !execution.portInvoked else { return }
        registry.settleCancelBeforePort(execution, by: capability)
        refreshSubmitting()
        refreshPending()
    }

    // MARK: - Projection publication

    private func publish(_ projection: AhaKeyStudioPageCommitProjection) {
        lastProjection = projection
        projectionRevision = AhaKeyStudioPageCommitExecutionRegistry
            .checkedIncrement(projectionRevision)
    }

    private func refreshSubmitting() {
        let next = registry.isOccupied
        if isSubmitting != next {
            isSubmitting = next
        }
    }

    private func refreshPending() {
        let pending = confirmationLedger.pending
        if pendingPrompt != pending {
            pendingPrompt = pending
        }
    }
}

// MARK: - Execution delegate

extension AhaKeyStudioPageCommitCoordinator: AhaKeyStudioPageCommitExecutionDelegate {
    func executionDidComplete(
        _ execution: AhaKeyStudioPageCommitExecution,
        portResult: Result<AhaKeyStudioPageCommitResult, Error>
    ) {
        refreshSubmitting()
        guard execution.originator === self else { return }

        let projection: AhaKeyStudioPageCommitProjection
        switch portResult {
        case .success(let result):
            confirmationLedger.applyCommitResult(
                result,
                attempt: execution.attempt,
                currentIdentity: execution.identity
            )
            editIntentLedger.applyCommitResult(
                result,
                attempt: execution.attempt,
                currentIdentity: execution.identity
            )
            let outcome = AhaKeyStudioPageCommitOutcome(result)
            lastOutcome = outcome
            projection = AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: outcome)
        case .failure(let error):
            confirmationLedger.noteAttemptFailed(
                attempt: execution.attempt,
                currentIdentity: execution.identity
            )
            editIntentLedger.noteAttemptFailed(
                attempt: execution.attempt,
                currentIdentity: execution.identity
            )
            let outcome = AhaKeyStudioPageCommitOutcome.failed(error.localizedDescription)
            lastOutcome = outcome
            projection = AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: outcome)
        }
        refreshPending()
        publish(projection)
    }

    func executionDidDiscard(
        _ execution: AhaKeyStudioPageCommitExecution,
        outcome: AhaKeyStudioPageCommitOutcome
    ) {
        refreshSubmitting()
        refreshPending()
        guard execution.originator === self else { return }
        // 不消费 ledger、不写 lastOutcome。
        publish(AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: outcome))
    }

    func executionOccupancyDidChange() {
        refreshSubmitting()
    }
}
