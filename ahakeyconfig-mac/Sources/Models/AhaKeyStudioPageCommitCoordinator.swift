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
@MainActor
struct AhaKeyStudioRuntimeStoreCommitPort: AhaKeyStudioPageCommitPort {
    let store: AhaKeyStudioRuntimeClient

    func commitFrozenPage(
        _ snapshot: AhaKeyStudioPageSnapshot,
        retryResidual: Bool
    ) async throws -> AhaKeyStudioPageCommitResult {
        try await store.commitFrozenPage(snapshot, retryResidual: retryResidual)
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

// MARK: - Per-attempt execution record

/// 单个 attempt 的执行租约。所有可变状态都是 per-attempt 的，
/// 旧 Task 不可能改写新 attempt 的状态。
@MainActor
final class AhaKeyStudioPageCommitExecution {
    /// 发起该 attempt 的 coordinator 身份。用于判断结算应交给哪个 session。
    let ownerToken: UUID
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
        ownerToken: UUID,
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
        self.ownerToken = ownerToken
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
    /// port 正常返回且未被丢弃：由 coordinator 消费 ledger 并投影。
    func executionDidComplete(
        _ execution: AhaKeyStudioPageCommitExecution,
        portResult: Result<AhaKeyStudioPageCommitResult, Error>
    )
    /// 结果被丢弃（identity 变化 / 用户取消）：**不消费 ledger、不写 lastOutcome**。
    func executionDidDiscard(
        _ execution: AhaKeyStudioPageCommitExecution,
        outcome: AhaKeyStudioPageCommitOutcome
    )
    /// 占用变化：coordinator 刷新 `isSubmitting`。
    func executionOccupancyDidChange()
}

/// **app-lifetime** 的 port 执行租约注册表。
///
/// 由 `AhaKeyStudioRuntimeClient` 持有并注入 coordinator（不是 static global，随 Store 生命周期）。
/// port 已进入且忽略取消时，租约**不随 coordinator 释放而消失**：任一 successor coordinator 的
/// `start` 都会看到被占用的租约并拒绝，直到旧 port 真正返回/抛错。
@MainActor
final class AhaKeyStudioPageCommitExecutionRegistry {
    static let traceCapacity = 64

    private(set) var lease: AhaKeyStudioPageCommitExecution?
    /// live identity 的观测版本。identity 真正变化时 checked 递增。
    private(set) var currentIdentity: AhaKeyStudioPageOverwriteConfirmationIdentity?
    private(set) var observationRevision: UInt64 = 0
    private(set) var attemptSequence: UInt64 = 0
    private(set) var clickCount: UInt64 = 0
    private(set) var portCallCount: UInt64 = 0
    /// 仅统计 **identity 变化**导致的丢弃。
    private(set) var supersededCount: UInt64 = 0
    /// 仅统计 **用户取消请求**次数（每次取消恰一次）。
    private(set) var cancelRequestedCount: UInt64 = 0
    private(set) var trace: [AhaKeyStudioPageCommitTraceEvent] = []

    private weak var delegate: (any AhaKeyStudioPageCommitExecutionDelegate)?
    private var task: Task<Void, Never>?
    private var traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?

    var isOccupied: Bool { lease != nil }

    /// successor coordinator 接管回调，并立即同步一次占用状态。
    func attach(delegate: any AhaKeyStudioPageCommitExecutionDelegate) {
        self.delegate = delegate
        delegate.executionOccupancyDidChange()
    }

    func setTraceSink(_ sink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?) {
        traceSink = sink
    }

    func observeIdentity(_ identity: AhaKeyStudioPageOverwriteConfirmationIdentity?) {
        if currentIdentity != identity {
            observationRevision = Self.checkedIncrement(observationRevision)
        }
        currentIdentity = identity
    }

    /// 占用租约并同步启动 port 调用段。已被占用时返回 false。
    @discardableResult
    func claim(
        _ execution: AhaKeyStudioPageCommitExecution,
        delegate: any AhaKeyStudioPageCommitExecutionDelegate
    ) -> Bool {
        guard lease == nil else { return false }
        lease = execution
        self.delegate = delegate
        record(.began(sequence: execution.sequence, pageID: execution.pageID, confirmed: execution.confirmed))
        startPortTask(execution)
        delegate.executionOccupancyDidChange()
        return true
    }

    /// 请求取消。只计一次 `cancelRequestedCount`，不触碰 `supersededCount`。
    func requestCancel() -> AhaKeyStudioPageCommitExecution? {
        guard let lease else { return nil }
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
    func settleCancelBeforePort(_ execution: AhaKeyStudioPageCommitExecution) {
        guard lease === execution else { return }
        record(.cancelSettled(
            sequence: execution.sequence,
            pageID: execution.pageID,
            confirmed: execution.confirmed,
            portInvoked: false
        ))
        release(execution)
        delegate?.executionDidDiscard(execution, outcome: .cancelled)
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

    func record(_ event: AhaKeyStudioPageCommitTraceEvent) {
        trace.append(event)
        if trace.count > Self.traceCapacity {
            trace.removeFirst(trace.count - Self.traceCapacity)
        }
        traceSink?(event)
    }

    private func release(_ execution: AhaKeyStudioPageCommitExecution) {
        guard lease === execution else { return }
        lease = nil
        task = nil
        delegate?.executionOccupancyDidChange()
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
    /// exact lease、observationRevision 与 live identity。
    private func admitPortEntry(_ execution: AhaKeyStudioPageCommitExecution) -> Bool {
        guard lease === execution else { return false }

        guard !Task.isCancelled,
              !execution.cancelRequested,
              observationRevision == execution.revisionAtSubmit,
              currentIdentity == execution.identity
        else {
            if execution.cancelRequested || Task.isCancelled {
                settleDiscarded(execution, portInvoked: false, outcome: .cancelled, isCancel: true)
            } else {
                noteIdentitySuperseded()
                settleDiscarded(execution, portInvoked: false, outcome: .superseded, isCancel: false)
            }
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

    private func settle(
        _ execution: AhaKeyStudioPageCommitExecution,
        portResult: Result<AhaKeyStudioPageCommitResult, Error>
    ) {
        guard lease === execution else { return }

        if execution.cancelRequested || Task.isCancelled {
            // 旧 port 返回后只做 cleanup：不消费 ledger、不写 lastOutcome。
            settleDiscarded(
                execution,
                portInvoked: execution.portInvoked,
                outcome: .cancelled,
                isCancel: true
            )
            return
        }

        if observationRevision != execution.revisionAtSubmit
            || currentIdentity != execution.identity {
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

        release(execution)
        delegate?.executionDidComplete(execution, portResult: portResult)
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
        release(execution)
        delegate?.executionDidDiscard(execution, outcome: outcome)
    }

    /// checked fail-closed increment：溢出是程序性错误，直接 trap，绝不回绕。
    static func checkedIncrement(_ value: UInt64) -> UInt64 {
        value + 1
    }
}

// MARK: - Coordinator

/// 两击提交的唯一可观测编排（C5G / C5GR1 / C5GR2 / C5GR3 / C5GR4）。
///
/// View 只调用同步 `start(_:port:)`。**执行租约由 app-lifetime 的注册表拥有**，
/// coordinator 只负责 ledger、chrome 投影与结果发布，因此 successor coordinator
/// 仍能看到在途租约并拒绝并行写。
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
    private let ownerToken = UUID()
    private var confirmationLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
    private var editIntentLedger = AhaKeyStudioPageEditIntentLedger()

    init(registry: AhaKeyStudioPageCommitExecutionRegistry) {
        self.registry = registry
        registry.attach(delegate: self)
    }

    // 观测口径转发到 app-lifetime 注册表，保证 successor coordinator 看到同一份事实。
    var currentIdentity: AhaKeyStudioPageOverwriteConfirmationIdentity? { registry.currentIdentity }
    var observationRevision: UInt64 { registry.observationRevision }
    var attemptSequence: UInt64 { registry.attemptSequence }
    var clickCount: UInt64 { registry.clickCount }
    var portCallCount: UInt64 { registry.portCallCount }
    var supersededCount: UInt64 { registry.supersededCount }
    var cancelRequestedCount: UInt64 { registry.cancelRequestedCount }
    var trace: [AhaKeyStudioPageCommitTraceEvent] { registry.trace }
    var inFlight: AhaKeyStudioPageCommitExecution? { registry.lease }

    /// 生产写入 Studio 现有 comm log；测试不设置 sink，只读 `trace`。
    func setTraceSink(_ sink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?) {
        registry.setTraceSink(sink)
    }

    // MARK: - Observation（View 驱动；Button click path 禁止调用）

    /// View 发布 live identity。这是唯一的 live 观测入口；
    /// `start` 与 Button click path 都不得调用它。
    func observeIdentity(_ identity: AhaKeyStudioPageOverwriteConfirmationIdentity?) {
        registry.observeIdentity(identity)
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

    /// 唯一提交入口（同步）。
    ///
    /// 同步阶段即占用 app-lifetime 租约并落 `began`；port 调用前还有第二次 pre-port fence。
    /// live identity 只由 `observeIdentity` 维护，本方法**不覆盖**它。
    func start(
        _ input: AhaKeyStudioPageSubmissionInput,
        port: any AhaKeyStudioPageCommitPort
    ) -> AhaKeyStudioPageCommitStartResult {
        registry.bumpClickCount()

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

        // 第一次 pre-port 一致性验证：冻结 input 必须等于已观测的 live identity。
        guard registry.currentIdentity == identity else {
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
            ownerToken: ownerToken,
            attempt: attempt,
            identity: identity,
            revisionAtSubmit: registry.observationRevision,
            sequence: registry.bumpAttemptSequence(),
            pageID: input.pageID,
            confirmed: confirmed,
            snapshot: input.frozenSnapshot(overwriteConfirmed: confirmed),
            retryResidual: input.retryResidual,
            port: port
        )
        guard registry.claim(execution, delegate: self) else {
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

    /// 页面关闭 / 对象释放 / 显式取消。
    ///
    /// - port 尚未进入：可安全立即释放租约，pre-port fence 保证旧 Task 永不调用 port。
    /// - port 已进入：`Task.cancel()` 只是协作式请求，**不能**作为副作用已停止的证明；
    ///   租约保留到旧 port 真正返回/抛错，期间任何 coordinator 的 `start` 都被拒绝。
    func cancelInFlight() {
        guard let execution = registry.requestCancel() else { return }
        refreshSubmitting()
        guard !execution.portInvoked else { return }
        registry.settleCancelBeforePort(execution)
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
        // 非本次 session 的 attempt（successor 接管）：不消费别人的 ledger，只收尾。
        guard execution.ownerToken == ownerToken else {
            refreshPending()
            return
        }

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
        guard execution.ownerToken == ownerToken else { return }
        // 不消费 ledger、不写 lastOutcome。
        publish(AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: outcome))
    }

    func executionOccupancyDidChange() {
        refreshSubmitting()
    }
}
