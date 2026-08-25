import Foundation

// MARK: - 配置事务状态机（WBS-5.6 切片 2）
//
// 纯决策层：把 5.1 WAL 持久记录（state/confirmedSteps）+ planner 计划折叠成
// 「下一步做什么」。不碰 IO——transport 执行结果以事件形式回流，状态推进全部
// 先落 WAL 再行动（崩溃即恢复点）。
// 语义对齐契约 `AhaKeyRuntimeOperationState`：
// - cancel：取消请求先入 cancellationRequested；已写步骤不回滚，
//   无写入则 failedWithoutWrites，有写入则 resumablePartial（可恢复）。
// - 永久失败：无写入 → failedWithoutWrites；有写入 → failedWithPartialCommit（终态）。
// - 断线：可重试错误 → paused/resumablePartial，等 recoveryCandidates 捞起重放。
// - 完成：全部步骤确认后由 WAL `commitOperationOutcome` 原子推进 baseline（revision 单调）。

public enum AhaKeyConfigurationTransactionEngine {

    // MARK: 步骤标识（确定性，恢复对账用）

    public static func stepIdentifiers(for plan: AhaKeyConfigurationPlanner.Plan) -> [AhaKeyRuntimeStepIdentifier] {
        plan.transactions.flatMap { transaction -> [AhaKeyRuntimeStepIdentifier] in
            switch transaction.kind {
            case .resourceUpload:
                return transaction.uploads.map {
                    // swiftlint:disable:next force_try
                    try! AhaKeyRuntimeStepIdentifier("resource:\($0.resource.logicalIdentifier.rawValue)")
                }
            case .baseConfiguration:
                return transaction.modeSlots.map {
                    // swiftlint:disable:next force_try
                    try! AhaKeyRuntimeStepIdentifier("base:mode:\($0)")
                }
            }
        }
    }

    // MARK: 事件

    public enum Event: Equatable, Sendable {
        /// 开始/接管一个已 accept 的事务（含恢复场景的重放入口）。
        case start
        case stepSucceeded(AhaKeyRuntimeStepIdentifier)
        /// 可重试失败（断线/超时）：事务保持可恢复。
        case stepFailedRetryable(AhaKeyRuntimeStepIdentifier)
        /// 永久失败（设备拒绝/校验失败）：进入终态。
        case stepFailedPermanent(AhaKeyRuntimeStepIdentifier)
        case cancelRequested
        /// 传输断开（等效于当前步可重试失败）。
        case disconnected
    }

    // MARK: 决策产物

    public enum Action: Equatable, Sendable {
        /// 执行下一步（先 confirmStep 已完成的，再下发此步）。
        case executeStep(AhaKeyRuntimeStepIdentifier)
        /// 无可执行步：全部确认 → 提交 completed + baseline（原子）。
        case commitCompleted
        /// 状态落 WAL：非终态推进（running / paused / cancellationRequested / resumablePartial）。
        case persistState(AhaKeyRuntimeOperationState)
        /// 终态落 WAL：failedWithoutWrites / failedWithPartialCommit（不得携带 baseline）。
        case commitTerminal(AhaKeyRuntimeOperationState)
        /// 无事发生（如重复事件/已终态）。
        case none
    }

    // MARK: 决策

    /// - Parameters:
    ///   - record: WAL 持久记录（nil = 尚未 accept，由调用方先走 store.accept）。
    ///   - confirmedSteps: WAL 已确认步骤。
    ///   - plan: planner 输出（步骤全集与顺序的唯一事实源）。
    public static func decide(
        event: Event,
        record: AhaKeyRuntimePersistedTransaction?,
        confirmedSteps: [AhaKeyRuntimeStepIdentifier],
        plan: AhaKeyConfigurationPlanner.Plan
    ) -> [Action] {
        guard let record else { return [.none] }
        // 终态不再响应任何事件
        guard !record.state.isTerminal else { return [.none] }

        let allSteps = stepIdentifiers(for: plan)
        let confirmed = Set(confirmedSteps)
        let nextStep = allSteps.first(where: { !confirmed.contains($0) })
        let hasWrites = !confirmed.isEmpty

        switch event {
        case .start:
            // 已请求取消的事务不因 start 复活执行
            guard record.state != .cancellationRequested else { return [.none] }
            var actions: [Action] = []
            if record.state == .accepted || record.state == .paused || record.state == .resumablePartial {
                actions.append(.persistState(.running))
            }
            if let nextStep { actions.append(.executeStep(nextStep)) }
            else { actions.append(.commitCompleted) }
            return actions

        case .stepSucceeded(let step):
            // 约定：调用方先把成功步 confirmStep 落 WAL，再携带最新 confirmedSteps 进决策。
            guard allSteps.contains(step), confirmed.contains(step) else { return [.none] }
            if let remaining = nextStep { return [.executeStep(remaining)] }
            return [.commitCompleted]

        case .stepFailedRetryable, .disconnected:
            // 有写入 → resumablePartial（HIL 断连恢复路径）；无写入 → paused
            return [.persistState(hasWrites ? .resumablePartial : .paused)]

        case .stepFailedPermanent:
            return [.commitTerminal(hasWrites ? .failedWithPartialCommit : .failedWithoutWrites)]

        case .cancelRequested:
            guard record.state != .cancellationRequested else { return [.none] }
            return [.persistState(.cancellationRequested)]
        }
    }

    /// 取消请求的终态结算：执行器在「当前步收尾后」调用。
    /// 无写入 → failedWithoutWrites；有写入 → resumablePartial（保可恢复，不强制失败）。
    public static func settleCancellation(
        confirmedSteps: [AhaKeyRuntimeStepIdentifier]
    ) -> Action {
        confirmedSteps.isEmpty ? .commitTerminal(.failedWithoutWrites) : .persistState(.resumablePartial)
    }
}
