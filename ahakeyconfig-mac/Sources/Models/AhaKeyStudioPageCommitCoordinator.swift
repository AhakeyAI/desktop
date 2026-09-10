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
    case began
    case returned
    case failed
    case superseded
}

enum AhaKeyStudioPageCommitTraceCategory: String, Equatable, Sendable {
    case portNotCalled
    case accepted
    case noOp
    case requiresOverwriteConfirmation
    case missingTrustedPageCache
    case unsupportedProfile
    case unsupportedPage
    case failed
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

    var traceCategory: AhaKeyStudioPageCommitTraceCategory {
        switch self {
        case .noOp: return .noOp
        case .requiresOverwriteConfirmation: return .requiresOverwriteConfirmation
        case .missingTrustedPageCache: return .missingTrustedPageCache
        case .unsupportedProfile: return .unsupportedProfile
        case .unsupportedPage: return .unsupportedPage
        case .accepted: return .accepted
        case .failed: return .failed
        case .ignoredInFlight: return .portNotCalled
        }
    }
}

/// 两击提交的唯一可观测编排（C5G）。
///
/// View 不再分别持有/分发 confirmation ledger 与 edit-intent ledger；按钮 action 只调用
/// `submit(_:port:)`。coordinator 内部拥有两个 ledger、exact current context、单次 in-flight
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
    private(set) var attemptSequence: UInt64 = 0
    private(set) var clickCount: UInt64 = 0
    private(set) var portCallCount: UInt64 = 0
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

    func observeIdentity(_ identity: AhaKeyStudioPageOverwriteConfirmationIdentity?) {
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

    /// 唯一提交入口。冻结输入 → 单次 attempt → 恰一次 port 调用 → 一次性 result/failure fan-out。
    @discardableResult
    func submit(
        _ input: AhaKeyStudioPageSubmissionInput,
        port: any AhaKeyStudioPageCommitPort
    ) async -> AhaKeyStudioPageCommitOutcome {
        clickCount &+= 1

        guard inFlightAttempt == nil else {
            record(
                pageID: input.pageID,
                confirmed: false,
                portCalled: false,
                category: .portNotCalled,
                phase: .superseded
            )
            return .ignoredInFlight
        }

        let identity = input.confirmationIdentity
        // 全部决策只来自这一份冻结输入。
        confirmationLedger.observeCurrentIdentity(identity)
        currentIdentity = identity
        let confirmed = confirmationLedger.shouldSubmitConfirmed(for: identity)
        let attempt = confirmationLedger.beginAttempt(for: identity)
        editIntentLedger.bindAttempt(attempt, fields: input.explicitIntentFieldIDs)
        inFlightAttempt = attempt

        attemptSequence &+= 1
        let sequence = attemptSequence
        isSubmitting = true
        record(
            pageID: input.pageID,
            confirmed: confirmed,
            portCalled: true,
            category: .portNotCalled,
            phase: .began,
            sequence: sequence
        )

        let outcome: AhaKeyStudioPageCommitOutcome
        do {
            portCallCount &+= 1
            let result = try await port.commitFrozenPage(
                input.frozenSnapshot(overwriteConfirmed: confirmed),
                retryResidual: input.retryResidual
            )
            // result consumption 只用冻结输入的 identity；绝不在 await 后重算 live identity。
            // 若期间 context 真变了，`observeIdentity` 已推进 revision 并作废 in-flight，
            // 这里的 consume 会拒绝，从而保留 C5ER1 stale/replay 因果。
            confirmationLedger.applyCommitResult(
                result,
                attempt: attempt,
                currentIdentity: identity
            )
            editIntentLedger.applyCommitResult(
                result,
                attempt: attempt,
                currentIdentity: identity
            )
            outcome = AhaKeyStudioPageCommitOutcome(result)
            record(
                pageID: input.pageID,
                confirmed: confirmed,
                portCalled: true,
                category: outcome.traceCategory,
                phase: .returned,
                sequence: sequence
            )
        } catch {
            confirmationLedger.noteAttemptFailed(attempt: attempt, currentIdentity: identity)
            editIntentLedger.noteAttemptFailed(attempt: attempt, currentIdentity: identity)
            outcome = .failed(error.localizedDescription)
            record(
                pageID: input.pageID,
                confirmed: confirmed,
                portCalled: true,
                category: .failed,
                phase: .failed,
                sequence: sequence
            )
        }

        inFlightAttempt = nil
        isSubmitting = false
        let pending = confirmationLedger.pending
        if pendingPrompt != pending {
            pendingPrompt = pending
        }
        lastOutcome = outcome
        return outcome
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
