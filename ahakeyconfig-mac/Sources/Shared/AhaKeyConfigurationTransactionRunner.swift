import Foundation

// MARK: - 配置事务执行器（WBS-5.6 切片 3）
//
// 把 `AhaKeyConfigurationTransactionEngine` 的纯决策接到 5.1 WAL 与 transport seam。
// 纪律：
// - 状态推进先落 WAL，再执行动作（崩溃即恢复点）；
// - 成功步先 confirmStep 再 decide 下一步；
// - 完成时由 commitOperationOutcome 原子推进 baseline（revision = base+1，内容与
//   package.desiredConfiguration 逐字一致，WAL 侧已强校验）；
// - 失败事务绝不携带 baseline（WAL 侧拒绝）。
// transport 以 StepExecutor 闭包注入，单测用假实现；真实 BLE 映射在切片 5。

public struct AhaKeyConfigurationStepFailure: Equatable, Sendable {
    public let retryable: Bool
    public let messageCode: AhaKeyRuntimeEventCode?
    public let context: AhaKeyRuntimeOperationFailureContext?

    public init(
        retryable: Bool,
        messageCode: AhaKeyRuntimeEventCode? = nil,
        context: AhaKeyRuntimeOperationFailureContext? = nil
    ) {
        self.retryable = retryable
        self.messageCode = messageCode
        self.context = context.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public enum AhaKeyConfigurationStepResult: Equatable, Sendable {
    case success
    /// 可重试（断线/超时）：事务进入 paused/resumablePartial。
    case retryableFailure
    /// 永久失败（设备拒绝/校验失败）：进入终态。
    case permanentFailure
    /// C-3：带稳定大类与可选结构化上下文的执行结果。旧调用方可继续用无 context 的两态。
    case failure(AhaKeyConfigurationStepFailure)
}

public enum AhaKeyConfigurationPreflightError: Error, Equatable, Sendable {
    /// 未知/不支持的 OLED 兼容剖面，禁止碰 CAS/WAL。
    case unsupportedProtocol
}

public struct AhaKeyConfigurationTransactionRunner {

    /// transport seam：执行一个步骤（resource upload / base config）。
    /// async：真实 BLE 执行包含 ACK/0x81 等待；同步假实现可直接返回字面量。
    public typealias StepExecutor = (AhaKeyRuntimeStepIdentifier) async -> AhaKeyConfigurationStepResult

    public let store: AhaKeyRuntimePersistentStore

    public init(store: AhaKeyRuntimePersistentStore) {
        self.store = store
    }

    /// 受理或接管一个 package 并跑到「完成 / 可恢复 / 终态」。
    /// 幂等：同 operationID 同 package 重入时走恢复路径（断线/重启后续跑）。
    @discardableResult
    public func run(
        package: AhaKeyConfigurationPackage,
        resourceFiles: [AhaKeyResourceIdentifier: URL],
        context: AhaKeyOLEDCompatibilityContext,
        release: AhaKeyReleaseFeatureProjection,
        pagePreconditions: AhaKeyRuntimePageExecutionPreconditions? = nil,
        execute: StepExecutor
    ) async throws -> AhaKeyRuntimeOperationState {
        guard context.allowsIngestAndApply else {
            throw AhaKeyConfigurationPreflightError.unsupportedProtocol
        }

        // 1. 受理（WAL accept：CAS 落资源 + 事务记录，幂等）
        try await store.accept(package, resourceFiles: resourceFiles)

        if package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion {
            return try await runPageScoped(
                package: package,
                context: context,
                pagePreconditions: pagePreconditions,
                execute: execute
            )
        }

        // 2. planner（密封 context + 容量校验）；拒绝即永久失败终态
        guard let desired = try? package.decodedConfigurationModel() else {
            return try await finishTerminal(
                package: package,
                hasWrites: false,
                messageCode: .configurationEncodingFailed
            )
        }
        let planning = AhaKeyConfigurationPlanner.plan(
            desired: desired,
            resources: package.resources,
            context: context,
            release: release
        )
        guard case .success(let plan) = planning else {
            return try await finishTerminal(
                package: package,
                hasWrites: false,
                messageCode: .configurationPlanRejected
            )
        }
        return try await runResolved(
            package: package,
            allSteps: AhaKeyConfigurationTransactionEngine.stepIdentifiers(for: plan),
            execute: execute
        )
    }

    /// 用户取消：schema=1 与 queued schema=2 落 cancellationRequested；
    /// running/paused/resumable 的 schema=2 page operation 拒绝普通取消。
    public func requestCancel(operationID: AhaKeyRuntimeOperationID) async throws {
        guard let record = try await store.transaction(operationID), !record.state.isTerminal else { return }
        if record.package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion {
            switch record.state {
            case .running, .paused, .resumablePartial:
                throw AhaKeyConfigurationCancelError.refusedWhileActive
            case .accepted, .cancellationRequested:
                break
            case .completed, .failedWithoutWrites, .failedWithPartialCommit:
                return
            }
        }
        try await persistNonTerminal(.cancellationRequested, package: record.package,
                               completed: record.completedSteps, total: record.totalSteps)
    }

    private func runPageScoped(
        package: AhaKeyConfigurationPackage,
        context: AhaKeyOLEDCompatibilityContext,
        pagePreconditions: AhaKeyRuntimePageExecutionPreconditions?,
        execute: StepExecutor
    ) async throws -> AhaKeyRuntimeOperationState {
        let confirmed = try await store.confirmedSteps(for: package.operationID)
        let pagePlan: AhaKeyRuntimePageExecutionPlan
        do {
            pagePlan = try AhaKeyRuntimePageSemantic.executionPlan(
                package: package,
                userSlotLimit: context.layout.userSlotLimit
            )
        } catch {
            return try await finishTerminal(
                package: package,
                hasWrites: pageDeviceWrites(package: package, confirmed: confirmed),
                messageCode: .configurationPlanRejected
            )
        }
        let hasDeviceWrites = AhaKeyRuntimePageSemantic.hasDeviceWrites(
            confirmed: confirmed,
            plan: pagePlan
        )
        do {
            try AhaKeyRuntimePageSemantic.evaluatePreflight(
                package: package,
                preconditions: pagePreconditions,
                hasDeviceWrites: hasDeviceWrites
            )
        } catch {
            return try await finishTerminal(
                package: package,
                hasWrites: hasDeviceWrites,
                messageCode: .configurationPreflightConflict
            )
        }
        let queue = try await store.durableDeviceQueue(package.targetDeviceID)
        if queue.isBlocked(package.operationID) {
            return try await store.transaction(package.operationID)?.state ?? .accepted
        }
        return try await runResolved(
            package: package,
            allSteps: pagePlan.identities,
            pagePlan: pagePlan,
            execute: execute
        )
    }

    private func runResolved(
        package: AhaKeyConfigurationPackage,
        allSteps: [AhaKeyRuntimeStepIdentifier],
        pagePlan: AhaKeyRuntimePageExecutionPlan? = nil,
        execute: StepExecutor
    ) async throws -> AhaKeyRuntimeOperationState {
        var confirmed = try await store.confirmedSteps(for: package.operationID)
        func hasWrites() -> Bool {
            if let pagePlan {
                return AhaKeyRuntimePageSemantic.hasDeviceWrites(confirmed: confirmed, plan: pagePlan)
            }
            return !confirmed.isEmpty
        }
        let totalSteps = UInt32(allSteps.count)
        var capturedMessageCode: AhaKeyRuntimeEventCode?
        var capturedContext: AhaKeyRuntimeOperationFailureContext?
        var actions = AhaKeyConfigurationTransactionEngine.decide(
            event: .start,
            record: try await store.transaction(package.operationID),
            confirmedSteps: confirmed,
            allSteps: allSteps,
            hasWrites: hasWrites()
        )
        while true {
            if let settled = try await settleCancellation(operationID: package.operationID) {
                return settled
            }
            guard let action = actions.first else {
                return try await store.transaction(package.operationID)?.state ?? .accepted
            }
            switch action {
            case .none:
                return try await store.transaction(package.operationID)?.state ?? .accepted
            case .persistState(let state):
                let attachFailure = state == .resumablePartial || state == .paused
                try await persistNonTerminal(
                    state,
                    package: package,
                    completed: UInt32(confirmed.count),
                    total: totalSteps,
                    messageCode: attachFailure ? capturedMessageCode : nil,
                    failureContext: attachFailure ? capturedContext : nil
                )
                actions.removeFirst()
            case .executeStep(let step):
                let report = unpacked(await execute(step), step: step)
                if report.success {
                    capturedMessageCode = nil
                    capturedContext = nil
                    try await store.confirmStep(step, for: package.operationID)
                    confirmed = try await store.confirmedSteps(for: package.operationID)
                    actions = AhaKeyConfigurationTransactionEngine.decide(
                        event: .stepSucceeded(step),
                        record: try await store.transaction(package.operationID),
                        confirmedSteps: confirmed,
                        allSteps: allSteps,
                        hasWrites: hasWrites()
                    )
                } else {
                    capturedMessageCode = report.messageCode
                    capturedContext = report.context
                    actions = AhaKeyConfigurationTransactionEngine.decide(
                        event: report.retryable ? .stepFailedRetryable(step) : .stepFailedPermanent(step),
                        record: try await store.transaction(package.operationID),
                        confirmedSteps: confirmed,
                        allSteps: allSteps,
                        hasWrites: hasWrites()
                    )
                }
            case .commitCompleted:
                let baseline = try AhaKeyRuntimeSyncBaseline(
                    deviceID: package.targetDeviceID,
                    revision: .init(package.baseRevision.rawValue + 1),
                    confirmedConfiguration: package.desiredConfiguration
                )
                try await store.commitOperationOutcome(
                    summary(package: package, state: .completed,
                            completed: UInt32(confirmed.count), total: UInt32(confirmed.count)),
                    syncBaseline: baseline
                )
                return .completed
            case .commitTerminal(let state):
                try await store.commitOperationOutcome(
                    summary(
                        package: package,
                        state: state,
                        completed: UInt32(confirmed.count),
                        total: totalSteps,
                        messageCode: capturedMessageCode,
                        failureContext: capturedContext
                    ),
                    syncBaseline: nil
                )
                return state
            }
        }
    }

    /// 取消结算（执行器在步间安全点调用）。
    public func settleCancellation(operationID: AhaKeyRuntimeOperationID) async throws -> AhaKeyRuntimeOperationState? {
        guard let record = try await store.transaction(operationID),
              record.state == .cancellationRequested else { return nil }
        let confirmed = try await store.confirmedSteps(for: operationID)
        let hasWrites: Bool
        if record.package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion {
            hasWrites = pageDeviceWrites(package: record.package, confirmed: confirmed)
        } else {
            hasWrites = !confirmed.isEmpty
        }
        switch AhaKeyConfigurationTransactionEngine.settleCancellation(
            confirmedSteps: confirmed,
            hasWrites: hasWrites
        ) {
        case .commitTerminal(let state):
            try await store.commitOperationOutcome(
                AhaKeyRuntimeOperationSummary(
                    id: operationID, targetDeviceID: record.package.targetDeviceID,
                    state: state, completedSteps: record.completedSteps,
                    totalSteps: record.totalSteps, messageCode: nil
                ),
                syncBaseline: nil
            )
            return state
        case .persistState(let state):
            try await persistNonTerminal(state, package: record.package,
                                   completed: record.completedSteps, total: record.totalSteps)
            return state
        default:
            return record.state
        }
    }

    // MARK: - 私有

    private struct StepReport {
        let success: Bool
        let retryable: Bool
        let messageCode: AhaKeyRuntimeEventCode?
        let context: AhaKeyRuntimeOperationFailureContext?
    }

    private func unpacked(
        _ result: AhaKeyConfigurationStepResult,
        step: AhaKeyRuntimeStepIdentifier
    ) -> StepReport {
        switch result {
        case .success:
            return StepReport(success: true, retryable: false, messageCode: nil, context: nil)
        case .retryableFailure:
            return StepReport(
                success: false,
                retryable: true,
                messageCode: nil,
                context: AhaKeyRuntimeOperationFailureContext(failedStepID: step)
            )
        case .permanentFailure:
            return StepReport(
                success: false,
                retryable: false,
                messageCode: nil,
                context: AhaKeyRuntimeOperationFailureContext(failedStepID: step)
            )
        case .failure(let detail):
            let context = (detail.context ?? AhaKeyRuntimeOperationFailureContext())
                .mergingMissingStep(step)
            return StepReport(
                success: false,
                retryable: detail.retryable,
                messageCode: detail.messageCode,
                context: context.isEmpty ? nil : context
            )
        }
    }

    private func summary(
        package: AhaKeyConfigurationPackage,
        state: AhaKeyRuntimeOperationState,
        completed: UInt32,
        total: UInt32,
        messageCode: AhaKeyRuntimeEventCode? = nil,
        failureContext: AhaKeyRuntimeOperationFailureContext? = nil
    ) -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: package.operationID,
            targetDeviceID: package.targetDeviceID,
            state: state,
            completedSteps: completed,
            totalSteps: total,
            messageCode: state == .completed ? nil : messageCode,
            failureContext: state == .completed ? nil : failureContext
        )
    }

    private func persistNonTerminal(
        _ state: AhaKeyRuntimeOperationState,
        package: AhaKeyConfigurationPackage,
        completed: UInt32,
        total: UInt32,
        messageCode: AhaKeyRuntimeEventCode? = nil,
        failureContext: AhaKeyRuntimeOperationFailureContext? = nil
    ) async throws {
        try await store.updateOperation(
            summary(
                package: package,
                state: state,
                completed: completed,
                total: total,
                messageCode: messageCode,
                failureContext: failureContext
            )
        )
    }

    private func pageDeviceWrites(
        package: AhaKeyConfigurationPackage,
        confirmed: [AhaKeyRuntimeStepIdentifier]
    ) -> Bool {
        let plan = try? AhaKeyRuntimePageSemantic.executionPlan(
            package: package,
            userSlotLimit: AhaKeyOLEDCompatibilityContext.standardUserSlotLimit
        )
        return AhaKeyRuntimePageSemantic.hasDeviceWrites(confirmed: confirmed, plan: plan)
    }

    private func finishTerminal(
        package: AhaKeyConfigurationPackage,
        hasWrites: Bool,
        messageCode: AhaKeyRuntimeEventCode?
    ) async throws -> AhaKeyRuntimeOperationState {
        let state: AhaKeyRuntimeOperationState = hasWrites ? .failedWithPartialCommit : .failedWithoutWrites
        try await store.commitOperationOutcome(
            summary(
                package: package,
                state: state,
                completed: 0,
                total: UInt32(package.resources.count),
                messageCode: messageCode
            ),
            syncBaseline: nil
        )
        return state
    }
}

private extension AhaKeyConfigurationPackage {
    /// 解码切片 0 冻结的声明式模型（失败 = 包体损坏，按永久失败处理）。
    func decodedConfigurationModel() throws -> AhaKeyDesiredConfiguration {
        try AhaKeyDesiredConfiguration.decode(from: desiredConfiguration)
    }
}
