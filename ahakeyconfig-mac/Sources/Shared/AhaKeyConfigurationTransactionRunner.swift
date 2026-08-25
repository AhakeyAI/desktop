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

public enum AhaKeyConfigurationStepResult: Equatable, Sendable {
    case success
    /// 可重试（断线/超时）：事务进入 paused/resumablePartial。
    case retryableFailure
    /// 永久失败（设备拒绝/校验失败）：进入终态。
    case permanentFailure
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
        capabilities: AhaKeyFirmwareCapabilities,
        protocolMode: AhaKeyProtocolMode,
        execute: StepExecutor
    ) async throws -> AhaKeyRuntimeOperationState {
        // 1. 受理（WAL accept：CAS 落资源 + 事务记录，幂等）
        try await store.accept(package, resourceFiles: resourceFiles)

        // 2. planner（current-only + 容量校验）；拒绝即永久失败终态
        guard let desired = try? package.decodedConfigurationModel() else {
            return try await finishTerminal(package: package, hasWrites: false)
        }
        let planning = AhaKeyConfigurationPlanner.plan(
            desired: desired,
            resources: package.resources,
            capabilities: capabilities,
            protocolMode: protocolMode
        )
        guard case .success(let plan) = planning else {
            return try await finishTerminal(package: package, hasWrites: false)
        }

        // 3. 决策-执行循环
        var confirmed = try await store.confirmedSteps(for: package.operationID)
        let totalSteps = UInt32(AhaKeyConfigurationTransactionEngine.stepIdentifiers(for: plan).count)
        var actions = AhaKeyConfigurationTransactionEngine.decide(
            event: .start,
            record: try await store.transaction(package.operationID),
            confirmedSteps: confirmed,
            plan: plan
        )
        while true {
            guard let action = actions.first else {
                return try await store.transaction(package.operationID)?.state ?? .accepted
            }
            switch action {
            case .none:
                return try await store.transaction(package.operationID)?.state ?? .accepted
            case .persistState(let state):
                try await persistNonTerminal(state, package: package,
                                       completed: UInt32(confirmed.count), total: totalSteps)
                actions.removeFirst()
            case .executeStep(let step):
                switch await execute(step) {
                case .success:
                    // 先落 WAL 再决策（崩溃即恢复点）
                    try await store.confirmStep(step, for: package.operationID)
                    confirmed = try await store.confirmedSteps(for: package.operationID)
                    actions = AhaKeyConfigurationTransactionEngine.decide(
                        event: .stepSucceeded(step),
                        record: try await store.transaction(package.operationID),
                        confirmedSteps: confirmed, plan: plan)
                case .retryableFailure:
                    actions = AhaKeyConfigurationTransactionEngine.decide(
                        event: .stepFailedRetryable(step),
                        record: try await store.transaction(package.operationID),
                        confirmedSteps: confirmed, plan: plan)
                case .permanentFailure:
                    actions = AhaKeyConfigurationTransactionEngine.decide(
                        event: .stepFailedPermanent(step),
                        record: try await store.transaction(package.operationID),
                        confirmedSteps: confirmed, plan: plan)
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
                    summary(package: package, state: state,
                            completed: UInt32(confirmed.count), total: totalSteps),
                    syncBaseline: nil
                )
                return state
            }
        }
    }

    /// 用户取消：落 cancellationRequested；当前步收尾后由调用方结算。
    public func requestCancel(operationID: AhaKeyRuntimeOperationID) async throws {
        guard let record = try await store.transaction(operationID), !record.state.isTerminal else { return }
        try await persistNonTerminal(.cancellationRequested, package: record.package,
                               completed: record.completedSteps, total: record.totalSteps)
    }

    /// 取消结算（执行器在步间安全点调用）。
    public func settleCancellation(operationID: AhaKeyRuntimeOperationID) async throws -> AhaKeyRuntimeOperationState? {
        guard let record = try await store.transaction(operationID),
              record.state == .cancellationRequested else { return nil }
        let confirmed = try await store.confirmedSteps(for: operationID)
        switch AhaKeyConfigurationTransactionEngine.settleCancellation(confirmedSteps: confirmed) {
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

    private func summary(
        package: AhaKeyConfigurationPackage,
        state: AhaKeyRuntimeOperationState,
        completed: UInt32, total: UInt32
    ) -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: package.operationID, targetDeviceID: package.targetDeviceID,
            state: state, completedSteps: completed, totalSteps: total, messageCode: nil
        )
    }

    private func persistNonTerminal(
        _ state: AhaKeyRuntimeOperationState,
        package: AhaKeyConfigurationPackage,
        completed: UInt32, total: UInt32
    ) async throws {
        try await store.updateOperation(summary(package: package, state: state, completed: completed, total: total))
    }

    private func finishTerminal(
        package: AhaKeyConfigurationPackage, hasWrites: Bool
    ) async throws -> AhaKeyRuntimeOperationState {
        let state: AhaKeyRuntimeOperationState = hasWrites ? .failedWithPartialCommit : .failedWithoutWrites
        try await store.commitOperationOutcome(
            summary(package: package, state: state, completed: 0,
                    total: UInt32(package.resources.count)),
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
