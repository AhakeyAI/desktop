import Foundation

/// 桥接 `AhaKeyRuntimePolicy` 与 `RuntimeModuleRegistry` 的策略化启停编排器。
///
/// 职责：
/// 1. 根据当前 policy 推导目标模块集合（`RuntimeModulePlan`）；
/// 2. 只在事实变化时通过 `RuntimeModuleRegistry` 执行并行启停；
/// 3. 提供 `shouldStayResident` 与模块状态 snapshot。
///
/// 线程安全：内部状态由 `actor` 隔离。
public actor RuntimeOrchestrator {
    public let registry: RuntimeModuleRegistry
    private var currentPolicy: AhaKeyRuntimePolicy
    private var currentPlan: RuntimeModulePlan

    public init(
        registry: RuntimeModuleRegistry = RuntimeModuleRegistry(),
        initialPolicy: AhaKeyRuntimePolicy = AhaKeyRuntimePolicy()
    ) {
        self.registry = registry
        self.currentPolicy = initialPolicy
        self.currentPlan = RuntimeOrchestratorCore.plan(for: initialPolicy)
    }

    /// 更新策略。只在 policy 或推导出的 plan 发生事实变化时才应用 transition。
    /// 返回实际发生的 transition；若 policy 未变化或 plan 未变化则返回 `nil`。
    @discardableResult
    public func updatePolicy(_ policy: AhaKeyRuntimePolicy) async -> RuntimeModuleTransition? {
        guard policy != currentPolicy else { return nil }
        let newPlan = RuntimeOrchestratorCore.plan(for: policy)
        guard let transition = RuntimeOrchestratorCore.transition(from: currentPlan, to: newPlan) else {
            currentPolicy = policy
            currentPlan = newPlan
            return nil
        }
        await registry.applyTransition(transition)
        currentPolicy = policy
        currentPlan = newPlan
        return transition
    }

    public var policy: AhaKeyRuntimePolicy { currentPolicy }
    public var plan: RuntimeModulePlan { currentPlan }
    public var shouldStayResident: Bool { currentPlan.shouldStayResident }

    public func snapshot() async -> [RuntimeModuleID: RuntimeModuleStatus] {
        await registry.snapshot()
    }
}
