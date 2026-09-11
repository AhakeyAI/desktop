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
    /// 结果因 live context 变化或取消而不被投影。
    case superseded
    /// 已有在途 attempt 或 frozen/live 不一致，未进入 attempt。
    case rejected
    /// 收到取消请求（port 可能在飞行中）。
    case cancelled
}

/// `.returned` 专用结果类型：只允许真实 commit 返回值，`pending` / `failed` /
/// `superseded` / `rejected` / `cancelled` 在**编译类型上不可构造**。
enum AhaKeyStudioPageCommitReturnedResult: String, Equatable, Sendable {
    case accepted
    case noOp
    case requiresOverwriteConfirmation
    case missingTrustedPageCache
    case unsupportedProfile
    case unsupportedPage

    init(_ outcome: AhaKeyStudioPageCommitOutcome) {
        switch outcome {
        case .accepted: self = .accepted
        case .noOp: self = .noOp
        case .requiresOverwriteConfirmation: self = .requiresOverwriteConfirmation
        case .missingTrustedPageCache: self = .missingTrustedPageCache
        case .unsupportedProfile: self = .unsupportedProfile
        case .unsupportedPage: self = .unsupportedPage
        case .failed, .superseded, .ignoredInFlight, .cancelled:
            assertionFailure("非 commit 返回结果不得进入 returned trace：\(outcome)")
            self = .noOp
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
    /// live context 变化 / 取消结算，旧结果不得投影。
    case superseded
    /// 已有在途 attempt / frozen 与 live 不一致，未产生 port 调用。
    case inFlightRejected
    /// 收到取消请求。
    case cancelled
}

/// 结构化 trace 事件：`phase` / `portInvoked` / `category` / `confirmed` 全部由 case 派生，
/// 矛盾的字段组合在产品类型层**不可构造**。
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
    case cancelled(
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
             .cancelled(let sequence, _, _, _):
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
             .cancelled(_, let pageID, _, _):
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
        case .cancelled: return .cancelled
        }
    }

    /// 该事件发生时 port 是否已被调用。
    var portInvoked: Bool {
        switch self {
        case .began, .rejected: return false
        case .portInvoked, .returned, .failed: return true
        case .superseded(_, _, _, let portInvoked): return portInvoked
        case .cancelled(_, _, _, let portInvoked): return portInvoked
        }
    }

    var category: AhaKeyStudioPageCommitTraceCategory {
        switch self {
        case .began, .portInvoked: return .pending
        case .returned(_, _, _, let result): return result.category
        case .failed: return .failed
        case .superseded: return .superseded
        case .rejected: return .inFlightRejected
        case .cancelled: return .cancelled
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
             .cancelled(_, _, let confirmed, _):
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
    /// 单次 in-flight 保护或 frozen/live 不一致：本次点击未产生 port 调用。
    case ignoredInFlight
    /// 页面关闭 / 对象释放 / 显式取消：在途 attempt 被取消。
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

/// `start(_:port:)` 的同步返回值。**不含 `Task`**：异步生命周期归 coordinator 所有。
enum AhaKeyStudioPageCommitStartResult: Equatable {
    /// attempt 已在同步阶段开始；终结结果经 `lastProjection` / `projectionRevision` 发布。
    case started
    /// 未进入 attempt（已有在途 attempt，或 frozen 与 live identity 不一致），已带终态投影。
    case rejected(AhaKeyStudioPageCommitProjection)
}

// MARK: - Per-attempt execution record

/// 单个 attempt 的执行占用（slot）。所有可变状态都是 per-attempt 的，
/// 旧 Task 不可能改写新 attempt 的状态。
@MainActor
final class AhaKeyStudioPageCommitExecution {
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

// MARK: - Coordinator

/// 两击提交的唯一可观测编排（C5G / C5GR1 / C5GR2 / C5GR3）。
///
/// View 只调用同步 `start(_:port:)`；coordinator 自持 in-flight `Task` 与 per-attempt 执行记录，
/// 终结结果经 `lastProjection` / `projectionRevision` 发布。
@MainActor
final class AhaKeyStudioPageCommitCoordinator: ObservableObject {
    /// 内存诊断环形缓冲上限。
    static let traceCapacity = 64

    @Published private(set) var pendingPrompt: AhaKeyStudioPageOverwriteConfirmationIdentity?
    @Published private(set) var isSubmitting = false
    @Published private(set) var lastOutcome: AhaKeyStudioPageCommitOutcome?
    /// 最近一次终结投影事件。View 经 `onChange(of: projectionRevision)` 消费。
    @Published private(set) var lastProjection: AhaKeyStudioPageCommitProjection?
    /// 每次发布终结投影时 checked 递增；单调值使重复同值投影也能被 View 观察到。
    @Published private(set) var projectionRevision: UInt64 = 0

    /// coordinator 跟踪的 exact current identity（**只**由 `observeIdentity` 推进）。
    private(set) var currentIdentity: AhaKeyStudioPageOverwriteConfirmationIdentity?
    /// live identity 的观测版本。identity 真正变化时 checked 递增。
    private(set) var observationRevision: UInt64 = 0
    private(set) var attemptSequence: UInt64 = 0
    private(set) var clickCount: UInt64 = 0
    private(set) var portCallCount: UInt64 = 0
    /// 因 live identity 变化 / 取消而未被投影的失效结果计数。
    private(set) var supersededCount: UInt64 = 0
    private(set) var trace: [AhaKeyStudioPageCommitTraceEvent] = []

    /// 当前执行占用。port 已在飞行且收到取消时**仍保留**，直到旧 port 真正返回/抛错。
    private(set) var inFlight: AhaKeyStudioPageCommitExecution?
    private var inFlightTask: Task<Void, Never>?
    private var confirmationLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
    private var editIntentLedger = AhaKeyStudioPageEditIntentLedger()
    private var traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?

    init(traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)? = nil) {
        self.traceSink = traceSink
    }

    deinit {
        // 释放 coordinator 时必须取消在途 Task（Task 不持有 coordinator，因此这里能真正跑到）。
        inFlightTask?.cancel()
    }

    /// 生产写入 Studio 现有 comm log；测试不设置 sink，只读 `trace`。
    func setTraceSink(_ sink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?) {
        traceSink = sink
    }

    // MARK: - Observation（View 驱动；Button click path 禁止调用）

    /// View 发布 live identity。这是 coordinator 唯一的 live 观测入口；
    /// `start` 与 Button click path 都不得调用它。
    func observeIdentity(_ identity: AhaKeyStudioPageOverwriteConfirmationIdentity?) {
        if currentIdentity != identity {
            observationRevision = Self.checkedIncrement(observationRevision)
        }
        confirmationLedger.observeCurrentIdentity(identity)
        currentIdentity = identity
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
    /// 同步阶段完成 clickCount / in-flight 判定 / sequence / `isSubmitting` / `began` trace；
    /// port 调用前还有**第二次 pre-port fence**（在内部 Task 被调度的同一 MainActor transition 上）。
    /// 因此「cancel-before-port 零调用」与「trace 缺 `began` = action 未触发」都成立。
    ///
    /// live identity 只由 `observeIdentity` 维护，本方法**不覆盖**它。
    func start(
        _ input: AhaKeyStudioPageSubmissionInput,
        port: any AhaKeyStudioPageCommitPort
    ) -> AhaKeyStudioPageCommitStartResult {
        clickCount = Self.checkedIncrement(clickCount)

        guard inFlight == nil else {
            record(.rejected(sequence: attemptSequence, pageID: input.pageID))
            let projection = AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .ignoredInFlight
            )
            publish(projection)
            return .rejected(projection)
        }

        let identity = input.confirmationIdentity

        // 第一次 pre-port 一致性验证：冻结 input 必须等于 View 已观测的 live identity。
        guard currentIdentity == identity else {
            supersededCount = Self.checkedIncrement(supersededCount)
            record(.superseded(
                sequence: attemptSequence,
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

        attemptSequence = Self.checkedIncrement(attemptSequence)
        let execution = AhaKeyStudioPageCommitExecution(
            attempt: attempt,
            identity: identity,
            revisionAtSubmit: observationRevision,
            sequence: attemptSequence,
            pageID: input.pageID,
            confirmed: confirmed,
            snapshot: input.frozenSnapshot(overwriteConfirmed: confirmed),
            retryResidual: input.retryResidual,
            port: port
        )
        inFlight = execution
        isSubmitting = true
        record(.began(sequence: execution.sequence, pageID: execution.pageID, confirmed: confirmed))

        // port 调用段**不捕获 coordinator**：await 期间不持有 self，因此 hung port 不构成保留环。
        let task = Task { @MainActor [weak self] in
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
        inFlightTask = task
        return .started
    }

    /// 第二次 pre-port fence：在 MainActor 同一 transition 上核 Task cancellation、
    /// exact in-flight attempt、observationRevision 与 live identity。
    /// 失败时零 port 调用、零 portCall 计数，只记 superseded/cancelled(portInvoked=false)。
    private func admitPortEntry(_ execution: AhaKeyStudioPageCommitExecution) -> Bool {
        // 已被 cancel-before-port 释放：零调用、零 trace（取消事件已在 cancelInFlight 记过）。
        guard inFlight === execution else { return false }

        guard !Task.isCancelled,
              !execution.cancelRequested,
              observationRevision == execution.revisionAtSubmit,
              currentIdentity == execution.identity
        else {
            if execution.cancelRequested || Task.isCancelled {
                settleSuperseded(execution, portInvoked: false, outcome: .cancelled)
            } else {
                settleSuperseded(execution, portInvoked: false)
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

    /// 页面关闭 / 对象释放 / 显式取消。
    ///
    /// - port 尚未进入：可安全立即释放 slot，pre-port fence 保证旧 Task 永不调用 port。
    /// - port 已进入：`Task.cancel()` 只是协作式请求，**不能**作为副作用已停止的证明；
    ///   保留执行占用直到旧 port 真正返回/抛错，期间新的 `start` 一律 rejected。
    func cancelInFlight() {
        guard let execution = inFlight else { return }
        execution.requestCancel()
        inFlightTask?.cancel()
        supersededCount = Self.checkedIncrement(supersededCount)
        record(.cancelled(
            sequence: execution.sequence,
            pageID: execution.pageID,
            confirmed: execution.confirmed,
            portInvoked: execution.portInvoked
        ))

        if execution.portInvoked {
            // 保留 slot；UI submitting 解除（可选），但执行占用保留。
            isSubmitting = false
            return
        }
        releaseSlot(execution)
        isSubmitting = false
        publish(AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: .cancelled))
    }

    // MARK: - Completion

    private func settle(
        _ execution: AhaKeyStudioPageCommitExecution,
        portResult: Result<AhaKeyStudioPageCommitResult, Error>
    ) {
        // 已被 cancel-before-port 释放：不得改写任何状态。
        guard inFlight === execution else { return }

        if execution.cancelRequested || Task.isCancelled {
            // port 返回后只做 cleanup，不消费 ledger、不投影旧 result。
            settleSuperseded(execution, portInvoked: execution.portInvoked, outcome: .cancelled)
            return
        }

        if observationRevision != execution.revisionAtSubmit
            || currentIdentity != execution.identity {
            settleSuperseded(execution, portInvoked: execution.portInvoked)
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
            record(.returned(
                sequence: execution.sequence,
                pageID: execution.pageID,
                confirmed: execution.confirmed,
                result: AhaKeyStudioPageCommitReturnedResult(outcome)
            ))
            projection = AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: outcome)
        case .failure(let error):
            confirmationLedger.noteAttemptFailed(attempt: execution.attempt, currentIdentity: execution.identity)
            editIntentLedger.noteAttemptFailed(attempt: execution.attempt, currentIdentity: execution.identity)
            let outcome = AhaKeyStudioPageCommitOutcome.failed(error.localizedDescription)
            record(.failed(
                sequence: execution.sequence,
                pageID: execution.pageID,
                confirmed: execution.confirmed
            ))
            projection = AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: outcome)
        }

        releaseSlot(execution)
        if projection.outcome.isProjectable {
            lastOutcome = projection.outcome
        }
        publish(projection)
    }

    private func settleSuperseded(
        _ execution: AhaKeyStudioPageCommitExecution,
        portInvoked: Bool,
        outcome: AhaKeyStudioPageCommitOutcome = .superseded
    ) {
        guard inFlight === execution else { return }
        supersededCount = Self.checkedIncrement(supersededCount)
        record(.superseded(
            sequence: execution.sequence,
            pageID: execution.pageID,
            confirmed: execution.confirmed,
            portInvoked: portInvoked
        ))
        releaseSlot(execution)
        publish(AhaKeyStudioPageCommitProjection(pageID: execution.pageID, outcome: outcome))
    }

    /// 释放在途执行占用。只释放占用的部分；投影/计数由调用方决定。
    private func releaseSlot(_ execution: AhaKeyStudioPageCommitExecution) {
        guard inFlight === execution else { return }
        inFlight = nil
        inFlightTask = nil
        isSubmitting = false
        let pending = confirmationLedger.pending
        if pendingPrompt != pending {
            pendingPrompt = pending
        }
    }

    // MARK: - Projection publication

    /// 发布终结投影事件。失效投影同样发布，但 View 对不可投影结果不触碰 status/toast。
    private func publish(_ projection: AhaKeyStudioPageCommitProjection) {
        lastProjection = projection
        projectionRevision = Self.checkedIncrement(projectionRevision)
    }

    // MARK: - Trace

    private func record(_ event: AhaKeyStudioPageCommitTraceEvent) {
        trace.append(event)
        if trace.count > Self.traceCapacity {
            trace.removeFirst(trace.count - Self.traceCapacity)
        }
        traceSink?(event)
    }

    /// checked fail-closed increment：溢出是程序性错误，直接 trap，绝不回绕。
    static func checkedIncrement(_ value: UInt64) -> UInt64 {
        value + 1
    }
}
