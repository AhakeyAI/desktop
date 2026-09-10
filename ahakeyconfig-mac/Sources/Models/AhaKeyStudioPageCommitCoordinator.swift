import Combine
import Foundation
import AhaKeyConfigShared

/// 一次点击冻结的提交输入。
///
/// 卡片 C5G 要求：`deviceID + session/transport generation + page/profile + selected set +
/// fields/baselines + explicit intent` 每次点击只冻结一次，identity、overwrite decision、
/// attempt token、Facade snapshot 与 result consumption 必须全部由同一份 frozen input 派生。
/// 本类型就是那份冻结值；`submit` 内部不再读取任何 live computed property。
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

/// typed trace：只含 pageID、attempt 序号、confirmed、result/error 类别、是否调用 port。
/// 不含资源字节、文件路径、用户文本或 secret。
enum AhaKeyStudioPageCommitTracePhase: String, Equatable, Sendable {
    /// 已进入 attempt，port 尚未被调用。
    case began
    case returned
    case failed
    /// 结果因 live identity 在 await 中变化而不被投影。
    case superseded
    /// 已有在途 attempt，本次点击被拒绝，未进入 attempt。
    case rejected
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
    /// 已有在途 attempt，本次点击未产生 port 调用。
    case inFlightRejected
}

struct AhaKeyStudioPageCommitTraceEvent: Equatable, Sendable {
    var sequence: UInt64
    var pageID: AhaKeyStudioPageID
    var confirmed: Bool
    var portCalled: Bool
    var category: AhaKeyStudioPageCommitTraceCategory
    var phase: AhaKeyStudioPageCommitTracePhase
}

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
    /// 单次 in-flight 保护：上一次提交尚未结束，本次点击未产生 port 调用。
    case ignoredInFlight

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
        case .superseded, .ignoredInFlight: return false
        case .noOp, .requiresOverwriteConfirmation, .missingTrustedPageCache,
             .unsupportedProfile, .unsupportedPage, .accepted, .failed:
            return true
        }
    }

    var traceCategory: AhaKeyStudioPageCommitTraceCategory {
        switch self {
        case .noOp: return .noOp
        case .requiresOverwriteConfirmation: return .requiresOverwriteConfirmation
        case .missingTrustedPageCache: return .missingTrustedPageCache
        case .unsupportedProfile: return .unsupportedProfile
        case .unsupportedPage: return .unsupportedPage
        case .accepted: return .accepted
        case .failed: return .failed
        case .superseded: return .superseded
        case .ignoredInFlight: return .inFlightRejected
        }
    }
}

/// 一次提交的投影。**携带冻结 pageID**：View 不得改用 live `currentPageID`/`currentPageChrome`
/// 展示结果，否则页面在 await 中切换后旧结果会被挂到新页面上。
struct AhaKeyStudioPageCommitProjection: Equatable, Sendable {
    var pageID: AhaKeyStudioPageID
    var outcome: AhaKeyStudioPageCommitOutcome
}

/// `AhaKeyStudioPageCommitCoordinator.start(_:port:)` 的同步返回值。
enum AhaKeyStudioPageCommitStart {
    /// attempt 已在**同步阶段**开始；结果在 port 返回后完成。
    case started(Task<AhaKeyStudioPageCommitProjection, Never>)
    /// 未进入 attempt（已有在途 attempt，或 frozen 与 live identity 不一致），已带终态投影。
    case rejected(AhaKeyStudioPageCommitProjection)
}

/// 两击提交的唯一可观测编排（C5G）。
///
/// View 不再分别持有/分发 confirmation ledger 与 edit-intent ledger；按钮 action 只调用
/// `start(_:port:)`。coordinator 内部拥有两个 ledger、exact current context、单次 in-flight
/// attempt、pending prompt 与 chrome 投影，以及 begin/result/failure 的一次性 fan-out。
@MainActor
final class AhaKeyStudioPageCommitCoordinator: ObservableObject {
    /// 内存诊断环形缓冲上限。
    static let traceCapacity = 64

    @Published private(set) var pendingPrompt: AhaKeyStudioPageOverwriteConfirmationIdentity?
    @Published private(set) var isSubmitting = false
    @Published private(set) var lastOutcome: AhaKeyStudioPageCommitOutcome?

    /// coordinator 跟踪的 exact current identity（由 View 的 observation 驱动，不在 await 中重算）。
    private(set) var currentIdentity: AhaKeyStudioPageOverwriteConfirmationIdentity?
    /// live identity 的观测版本。每次 live identity 真正变化时递增；用于判定 await 期间是否失效。
    private(set) var observationRevision: UInt64 = 0
    private(set) var attemptSequence: UInt64 = 0
    private(set) var clickCount: UInt64 = 0
    private(set) var portCallCount: UInt64 = 0
    /// 因 live identity 变化而未被投影的失效结果计数。
    private(set) var supersededCount: UInt64 = 0
    private(set) var trace: [AhaKeyStudioPageCommitTraceEvent] = []

    private var confirmationLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
    private var editIntentLedger = AhaKeyStudioPageEditIntentLedger()
    private var inFlightAttempt: AhaKeyStudioPageOverwriteConfirmationAttemptToken?
    private var traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?

    init(traceSink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)? = nil) {
        self.traceSink = traceSink
    }

    /// 生产写入 Studio 现有 comm log；测试不设置 sink，只读 `trace`。
    func setTraceSink(_ sink: ((AhaKeyStudioPageCommitTraceEvent) -> Void)?) {
        traceSink = sink
    }

    // MARK: - Observation（View 驱动）

    /// View 发布 live identity。这是 coordinator 唯一的 live 观测入口；
    /// `submit` 不得用它覆盖 live identity。
    func observeIdentity(_ identity: AhaKeyStudioPageOverwriteConfirmationIdentity?) {
        if currentIdentity != identity {
            observationRevision &+= 1
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

    /// 同步启动一次点击。
    ///
    /// **必须在返回事件循环前**完成 clickCount / in-flight 判定 / sequence / `isSubmitting` /
    /// `began` trace 的设置：只有这样，「trace 缺 `began`」才严格等价于「Button action 未触发」。
    /// port 的 async 调用由本方法内部启动，View 不得先建 Task 再进入 coordinator。
    ///
    /// live identity 只由 `observeIdentity` 维护，本方法**不覆盖**它。
    func start(
        _ input: AhaKeyStudioPageSubmissionInput,
        port: any AhaKeyStudioPageCommitPort
    ) -> AhaKeyStudioPageCommitStart {
        clickCount &+= 1

        guard inFlightAttempt == nil else {
            record(
                pageID: input.pageID,
                confirmed: false,
                portCalled: false,
                category: .inFlightRejected,
                phase: .rejected
            )
            return .rejected(AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .ignoredInFlight
            ))
        }

        let identity = input.confirmationIdentity

        // 进入 port 前的一致性验证：冻结 input 必须等于 View 已观测的 live identity。
        // 不匹配时不得 beginAttempt / 不得调用 port，也就不会用 frozen 覆盖 live。
        guard currentIdentity == identity else {
            supersededCount &+= 1
            record(
                pageID: input.pageID,
                confirmed: false,
                portCalled: false,
                category: .superseded,
                phase: .superseded
            )
            return .rejected(AhaKeyStudioPageCommitProjection(
                pageID: input.pageID,
                outcome: .superseded
            ))
        }

        let revisionAtSubmit = observationRevision
        let confirmed = confirmationLedger.shouldSubmitConfirmed(for: identity)
        let attempt = confirmationLedger.beginAttempt(for: identity)
        editIntentLedger.bindAttempt(attempt, fields: input.explicitIntentFieldIDs)
        inFlightAttempt = attempt

        attemptSequence &+= 1
        let sequence = attemptSequence
        isSubmitting = true
        // `.began` 时 port 尚未被调用：portCalled=false，category=pending。
        record(
            pageID: input.pageID,
            confirmed: confirmed,
            portCalled: false,
            category: .pending,
            phase: .began,
            sequence: sequence
        )

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return AhaKeyStudioPageCommitProjection(pageID: input.pageID, outcome: .superseded)
            }
            return await self.finish(
                input,
                identity: identity,
                attempt: attempt,
                confirmed: confirmed,
                revisionAtSubmit: revisionAtSubmit,
                sequence: sequence,
                port: port
            )
        }
        return .started(task)
    }

    /// port 调用与结果收口。await 后若 live context 已变化，只能产生 typed superseded。
    private func finish(
        _ input: AhaKeyStudioPageSubmissionInput,
        identity: AhaKeyStudioPageOverwriteConfirmationIdentity,
        attempt: AhaKeyStudioPageOverwriteConfirmationAttemptToken,
        confirmed: Bool,
        revisionAtSubmit: UInt64,
        sequence: UInt64,
        port: any AhaKeyStudioPageCommitPort
    ) async -> AhaKeyStudioPageCommitProjection {
        let projection: AhaKeyStudioPageCommitProjection
        do {
            portCallCount &+= 1
            let result = try await port.commitFrozenPage(
                input.frozenSnapshot(overwriteConfirmed: confirmed),
                retryResidual: input.retryResidual
            )
            if isStale(since: revisionAtSubmit, identity: identity) {
                // await 期间 live context 变化：结果已失效，不消费、不投影。
                projection = supersede(input: input, confirmed: confirmed, sequence: sequence, portCalled: true)
            } else {
                confirmationLedger.applyCommitResult(result, attempt: attempt, currentIdentity: identity)
                editIntentLedger.applyCommitResult(result, attempt: attempt, currentIdentity: identity)
                let outcome = AhaKeyStudioPageCommitOutcome(result)
                record(
                    pageID: input.pageID,
                    confirmed: confirmed,
                    portCalled: true,
                    category: outcome.traceCategory,
                    phase: .returned,
                    sequence: sequence
                )
                projection = AhaKeyStudioPageCommitProjection(pageID: input.pageID, outcome: outcome)
            }
        } catch {
            if isStale(since: revisionAtSubmit, identity: identity) {
                projection = supersede(input: input, confirmed: confirmed, sequence: sequence, portCalled: true)
            } else {
                confirmationLedger.noteAttemptFailed(attempt: attempt, currentIdentity: identity)
                editIntentLedger.noteAttemptFailed(attempt: attempt, currentIdentity: identity)
                let outcome = AhaKeyStudioPageCommitOutcome.failed(error.localizedDescription)
                record(
                    pageID: input.pageID,
                    confirmed: confirmed,
                    portCalled: true,
                    category: .failed,
                    phase: .failed,
                    sequence: sequence
                )
                projection = AhaKeyStudioPageCommitProjection(pageID: input.pageID, outcome: outcome)
            }
        }

        inFlightAttempt = nil
        isSubmitting = false
        let pending = confirmationLedger.pending
        if pendingPrompt != pending {
            pendingPrompt = pending
        }
        // 失效结果不得进入 `lastOutcome`，因此也不会被任何投影面当作当前页结果。
        if projection.outcome.isProjectable {
            lastOutcome = projection.outcome
        }
        return projection
    }

    /// attempt 是否已因 live context 变化而失效。
    private func isStale(
        since revisionAtSubmit: UInt64,
        identity: AhaKeyStudioPageOverwriteConfirmationIdentity
    ) -> Bool {
        observationRevision != revisionAtSubmit || currentIdentity != identity
    }

    private func supersede(
        input: AhaKeyStudioPageSubmissionInput,
        confirmed: Bool,
        sequence: UInt64,
        portCalled: Bool
    ) -> AhaKeyStudioPageCommitProjection {
        supersededCount &+= 1
        record(
            pageID: input.pageID,
            confirmed: confirmed,
            portCalled: portCalled,
            category: .superseded,
            phase: .superseded,
            sequence: sequence
        )
        return AhaKeyStudioPageCommitProjection(pageID: input.pageID, outcome: .superseded)
    }

    // MARK: - Trace

    /// 供 HIL/证据读取的一次性快照。
    func traceSnapshot() -> [AhaKeyStudioPageCommitTraceEvent] { trace }

    private func record(
        pageID: AhaKeyStudioPageID,
        confirmed: Bool,
        portCalled: Bool,
        category: AhaKeyStudioPageCommitTraceCategory,
        phase: AhaKeyStudioPageCommitTracePhase,
        sequence: UInt64? = nil
    ) {
        let event = AhaKeyStudioPageCommitTraceEvent(
            sequence: sequence ?? attemptSequence,
            pageID: pageID,
            confirmed: confirmed,
            portCalled: portCalled,
            category: category,
            phase: phase
        )
        trace.append(event)
        if trace.count > Self.traceCapacity {
            trace.removeFirst(trace.count - Self.traceCapacity)
        }
        traceSink?(event)
    }
}
