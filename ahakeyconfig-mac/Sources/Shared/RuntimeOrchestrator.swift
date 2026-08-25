import Foundation

/// Runtime 编排器：策略驱动的模块启停唯一入口（WBS 5.4 切片 3）。
///
/// 组合 `RuntimeOrchestratorCore`（策略→模块集合、变更检测）与
/// `RuntimeModuleRegistry`（并发启停、错误隔离）：
/// - `applyPolicy` 只在事实变化时应用并返回 transition（正常轮询零发布）；
/// - keep-alive/常驻性由策略单一推导（`plan.shouldStayResident`），
///   不存在第二处决策；
/// - 全部增强关闭 → 所有模块停止（Runtime 本体是否退出由宿主进程语义决定，
///   见任务卡执行记录：launchd KeepAlive 下进程退出会立即重拉，本卡选择
///   「模块全停、进程空闲驻留」作为有界形态，CPU 实测 0.0%）。
public actor RuntimeOrchestrator {
    private let registry = RuntimeModuleRegistry()
    private var currentPlan = RuntimeModulePlan(desiredModules: [])

    public init() {}

    /// 注册模块（仅登记，不启动；启动由 applyPolicy 驱动）。
    public func register(_ module: any RuntimeModule) async {
        await registry.register(module)
    }

    /// 应用新策略。返回实际发生的 transition；无变化返回 `nil`（调用方不得发布）。
    @discardableResult
    public func applyPolicy(_ policy: AhaKeyRuntimePolicy) async -> RuntimeModuleTransition? {
        let next = RuntimeOrchestratorCore.plan(for: policy)
        guard let transition = RuntimeOrchestratorCore.transition(from: currentPlan, to: next)
        else { return nil }
        await registry.applyTransition(transition)
        currentPlan = next
        return transition
    }

    /// 当前是否有任一增强模块应常驻运行。
    public var shouldStayResident: Bool { currentPlan.shouldStayResident }

    /// 当前各模块状态快照。
    public func moduleStatuses() async -> [RuntimeModuleID: RuntimeModuleStatus] {
        await registry.snapshot()
    }

    /// 进程退出清理：停止全部模块。
    public func stopAll() async {
        await registry.stopAll()
        currentPlan = RuntimeModulePlan(desiredModules: [])
    }
}
