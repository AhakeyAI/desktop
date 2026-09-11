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
    /// 内部 Task 已实际进入 port 调用。
    case portInvoked
    case returned
    case failed
    /// 结果因 live context 变化而不被投影。
    case superseded
    /// 已有在途 attempt 或 frozen/live 不一致，未进入 attempt。
    case rejected
    /// 页面关闭/对象释放，在途 attempt 被取消。
    case cancelled
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
    /// live context 变化，旧结果不得投影。
    case superseded
    /// 已有在途 attempt / frozen 与 live 不一致，未产生 port 调用。
    case inFlightRejected
    case cancelled
}

/// 结构化 trace 事件：`phase` / `portInvoked` / `category` 全部由 case 派生，
/// 矛盾的字段组合在产品类型层**不可构造**。
enum AhaKeyStudioPageCommitTraceEvent: Equatable, Sendable {
    case began(sequence: UInt64, pageID: AhaKeyStudioPageID, confirmed: Bool)
    case portInvoked(sequence: UInt64, pageID: AhaKeyStudioPageID, confirmed: Bool)
    case returned(
        sequence: UInt64,
        pageID: AhaKeyStudioPageID,
        confirmed: Bool,
        category: AhaKeyStudioPageCommitTraceCategory
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
        case .returned(_, _, _, let category): return category
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
    /// 页面关闭 / 对象释放：在途 attempt 被取消。
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

// MARK: - Coordinator

/// 两击提交的唯一可观测编排（C5G / C5GR1 / C5GR2）。
///
/// View 不再分别持有/分发 confirmation ledger 与 edit-intent ledger；按钮 action 只调用
/// `start(_:port:)`。coordinator 内部拥有两个 ledger、exact current context、
/// 单次 in-flight attempt 与其 `Task`、pending prompt 与 chrome 投影、一次性 fan-out，
/// 以及非敏感结构化 trace。
@MainActor
final class AhaKeyStudioPageCommitCoordinator: ObservableObject {
    /// 内存诊断环形缓冲上限。
    static let traceCapacity = 64

    @Published private(set) var pendingPrompt: AhaKeyStudioPageOverwriteConfirmationIdentity?
    @Published private(set) var isSubmitting = false
    @Published private(set) var lastOutcome: AhaKeyStudioPageCommitOutcome?
    /// 最近一次终结投影事件。View 经 `onChange(of: projectionRevision)` 消费，
    /// 因此 coordinator 拥有异步生命周期，View 既不需要闭包也不需要建 Task。
    @Published private(set) var lastProjection: AhaKeyStudioPageCommitProjection?
    /// 每次发布终结投影时 checked 递增；单调值使重复同值投影也能被 View 观察到。
    @Published private(set) var projectionRevision: UInt64 = 0

    /// coordinator 跟踪的 exact current identity（**只**由 `observeIdentity` 推进）。
    private(set) var currentIdentity: AhaKeyStudioPageOverwriteConfirmationIdentity?
    /// live identity 的观测版本。identity 真正变化时 checked 递增；用于判定 await 期间是否失效。
    private(set) var observationRevision: UInt64 = 0
    private(set) var attemptSequence: UInt64 = 0
    private(set) var clickCount: UInt64 = 0
    private(set) var portCallCount: UInt64 = 0
    /// 因 live identity 变化 / 取消而未被投影的失效结果计数。
    private(set) var supersededCount: UInt64 = 0
    private(set) var trace: [AhaKeyStudioPageCommitTraceEvent] = []

    private var confirmationLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
    private var editIntentLedger = AhaKeyStudioPageEditIntentLedger()
    private var inFlightAttempt: AhaKeyStudioPageOverwriteConfirmationAttemptToken?
    private var inFlightTask: Task<Void, Never>?
    private var inFlightPageID: AhaKeyStudioPageID?
    private var inFlightConfirmed = false
    private var inFlightPortInvoked = false
    private var traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?

    init(traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)? = nil) {
        self.traceSink = traceSink
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
    /// **必须在返回事件循环前**完成 clickCount / in-flight 判定 / sequence / `isSubmitting` /
    /// `began` trace 的设置：只有这样，「trace 缺 `began`」才严格等价于「Button action 未触发」。
    ///
    /// 异步生命周期由 coordinator 自己持有（`inFlightTask`）；View 只提供完成回调，不得建 Task。
    /// live identity 只由 `observeIdentity` 维护，本方法**不覆盖**它。
    func start(
        _ input: AhaKeyStudioPageSubmissionInput,
        port: any AhaKeyStudioPageCommitPort
    ) -> AhaKeyStudioPageCommitStartResult {
        clickCount = Self.checkedIncrement(clickCount)

        guard inFlightAttempt == nil else {
            record(.rejected(sequence: attemptSequence, pageID: input.pageID))
            let projection = AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .ignoredInFlight
            )
            publish(projection)
            return .rejected(projection)
        }

        let identity = input.confirmationIdentity

        // 进入 port 前的一致性验证：冻结 input 必须等于 View 已观测的 live identity。
        // 不匹配时不得 beginAttempt / 不得调用 port，也就不会用 frozen 覆盖 live。
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

        let revisionAtSubmit = observationRevision
        let confirmed = confirmationLedger.shouldSubmitConfirmed(for: identity)
        let attempt = confirmationLedger.beginAttempt(for: identity)
        editIntentLedger.bindAttempt(attempt, fields: input.explicitIntentFieldIDs)
        inFlightAttempt = attempt

        attemptSequence = Self.checkedIncrement(attemptSequence)
        let sequence = attemptSequence
        isSubmitting = true
        inFlightPageID = input.pageID
        inFlightConfirmed = confirmed
        inFlightPortInvoked = false
        record(.began(sequence: sequence, pageID: input.pageID, confirmed: confirmed))

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let projection = await self.finish(
                input,
                identity: identity,
                attempt: attempt,
                confirmed: confirmed,
                revisionAtSubmit: revisionAtSubmit,
                sequence: sequence,
                port: port
            )
            self.publish(projection)
        }
        inFlightTask = task
        return .started
    }

    /// 页面关闭 / 对象释放：取消在途 attempt，确保 port 悬挂不会永久保留 submitting / in-flight。
    /// 迟到的 port 结果不会再被消费或投影（`finish` 的 stale 判定包含 attempt 身份）。
    func cancelInFlight() {
        guard inFlightAttempt != nil else { return }
        let pageID = inFlightPageID
        let confirmed = inFlightConfirmed
        let portInvoked = inFlightPortInvoked
        inFlightTask?.cancel()
        inFlightTask = nil
        inFlightAttempt = nil
        inFlightPageID = nil
        inFlightConfirmed = false
        inFlightPortInvoked = false
        isSubmitting = false
        supersededCount = Self.checkedIncrement(supersededCount)
        if let pageID {
            record(.cancelled(
                sequence: attemptSequence,
                pageID: pageID,
                confirmed: confirmed,
                portInvoked: portInvoked
            ))
        }
    }

    // MARK: - Completion

    private func finish(
        _ input: AhaKeyStudioPageSubmissionInput,
        identity: AhaKeyStudioPageOverwriteConfirmationIdentity,
        attempt: AhaKeyStudioPageOverwriteConfirmationAttemptToken,
        confirmed: Bool,
        revisionAtSubmit: UInt64,
        sequence: UInt64,
        port: any AhaKeyStudioPageCommitPort
    ) async -> AhaKeyStudioPageCommitProjection {
        portCallCount = Self.checkedIncrement(portCallCount)
        inFlightPortInvoked = true
        // `began` 只证明 Button 同步进入；`portInvoked` 证明内部 Task 已实际调用 port。
        record(.portInvoked(sequence: sequence, pageID: input.pageID, confirmed: confirmed))

        let projection: AhaKeyStudioPageCommitProjection
        do {
            let result = try await port.commitFrozenPage(
                input.frozenSnapshot(overwriteConfirmed: confirmed),
                retryResidual: input.retryResidual
            )
            if isStale(since: revisionAtSubmit, identity: identity, attempt: attempt) {
                projection = supersede(input: input, confirmed: confirmed, sequence: sequence, portInvoked: true)
            } else {
                confirmationLedger.applyCommitResult(result, attempt: attempt, currentIdentity: identity)
                editIntentLedger.applyCommitResult(result, attempt: attempt, currentIdentity: identity)
                let outcome = AhaKeyStudioPageCommitOutcome(result)
                record(.returned(
                    sequence: sequence,
                    pageID: input.pageID,
                    confirmed: confirmed,
                    category: Self.traceCategory(for: outcome)
                ))
                projection = AhaKeyStudioPageCommitProjection(pageID: input.pageID, outcome: outcome)
            }
        } catch {
            if isStale(since: revisionAtSubmit, identity: identity, attempt: attempt) {
                projection = supersede(input: input, confirmed: confirmed, sequence: sequence, portInvoked: true)
            } else {
                confirmationLedger.noteAttemptFailed(attempt: attempt, currentIdentity: identity)
                editIntentLedger.noteAttemptFailed(attempt: attempt, currentIdentity: identity)
                let outcome = AhaKeyStudioPageCommitOutcome.failed(error.localizedDescription)
                record(.failed(sequence: sequence, pageID: input.pageID, confirmed: confirmed))
                projection = AhaKeyStudioPageCommitProjection(pageID: input.pageID, outcome: outcome)
            }
        }

        // 只有仍属本次 attempt 时才收尾；已被取消的 attempt 不再改动 submitting/pending。
        if inFlightAttempt == attempt {
            inFlightAttempt = nil
            inFlightTask = nil
            inFlightPageID = nil
            inFlightConfirmed = false
            inFlightPortInvoked = false
            isSubmitting = false
            let pending = confirmationLedger.pending
            if pendingPrompt != pending {
                pendingPrompt = pending
            }
        }
        // 失效结果不得进入 `lastOutcome`，因此也不会被任何投影面当作当前页结果。
        if projection.outcome.isProjectable {
            lastOutcome = projection.outcome
        }
        return projection
    }

    /// attempt 是否已失效：live context 变化，或已被取消。
    private func isStale(
        since revisionAtSubmit: UInt64,
        identity: AhaKeyStudioPageOverwriteConfirmationIdentity,
        attempt: AhaKeyStudioPageOverwriteConfirmationAttemptToken
    ) -> Bool {
        inFlightAttempt != attempt
            || observationRevision != revisionAtSubmit
            || currentIdentity != identity
    }

    private func supersede(
        input: AhaKeyStudioPageSubmissionInput,
        confirmed: Bool,
        sequence: UInt64,
        portInvoked: Bool
    ) -> AhaKeyStudioPageCommitProjection {
        supersededCount = Self.checkedIncrement(supersededCount)
        record(.superseded(
            sequence: sequence,
            pageID: input.pageID,
            confirmed: confirmed,
            portInvoked: portInvoked
        ))
        return AhaKeyStudioPageCommitProjection(pageID: input.pageID, outcome: .superseded)
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

    static func traceCategory(
        for outcome: AhaKeyStudioPageCommitOutcome
    ) -> AhaKeyStudioPageCommitTraceCategory {
        switch outcome {
        case .noOp: return .noOp
        case .requiresOverwriteConfirmation: return .requiresOverwriteConfirmation
        case .missingTrustedPageCache: return .missingTrustedPageCache
        case .unsupportedProfile: return .unsupportedProfile
        case .unsupportedPage: return .unsupportedPage
        case .accepted: return .accepted
        case .failed: return .failed
        case .superseded: return .superseded
        case .ignoredInFlight: return .inFlightRejected
        case .cancelled: return .cancelled
        }
    }

    /// checked fail-closed increment：溢出是程序性错误，直接 trap，绝不回绕。
    /// UInt64 以每秒一次计需约 5.8×10^11 年才可能触达，因此现实中不可达。
    static func checkedIncrement(_ value: UInt64) -> UInt64 {
        value + 1
    }
}
