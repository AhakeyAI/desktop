import Foundation

/// RuntimeOrchestrator 管辖的后台模块标识。
///
/// 与计划 §9.1 的模块分解对齐；`SessionRoutingModule`/`DeviceRuntimeModule`
/// 分别属于 WBS 5A 与 5.5，本卡不引入。
public enum RuntimeModuleID: String, Codable, CaseIterable, Hashable, Sendable {
    case ahaType
    case aiIntegration
    case dynamicLighting
    case powerProtection
}

/// 由策略推导出的模块目标集合。纯数据，不含副作用。
public struct RuntimeModulePlan: Equatable, Sendable {
    public var desiredModules: Set<RuntimeModuleID>

    public init(desiredModules: Set<RuntimeModuleID>) {
        self.desiredModules = desiredModules
    }

    /// 全部增强功能关闭时 Runtime 不得无条件常驻（计划 §9.1、任务卡完成定义）。
    public var shouldStayResident: Bool { !desiredModules.isEmpty }
}

/// 两次 plan 之间的事实变化。`nil` 表示无变化——Snapshot/Event 只在事实变化时发布。
public struct RuntimeModuleTransition: Equatable, Sendable {
    public var started: Set<RuntimeModuleID>
    public var stopped: Set<RuntimeModuleID>
    /// Runtime 常驻性的变化（true=开始常驻，false=应退出），无变化为 nil。
    public var residencyChanged: Bool?

    public init(started: Set<RuntimeModuleID>, stopped: Set<RuntimeModuleID>, residencyChanged: Bool?) {
        self.started = started
        self.stopped = stopped
        self.residencyChanged = residencyChanged
    }
}

/// 策略 → 模块编排的纯 reducer。不含进程副作用，方便 red→green 驱动。
public enum RuntimeOrchestratorCore {
    /// 从冻结契约 `AhaKeyRuntimePolicy` 推导目标模块集合：
    /// - `ahaType.enabled` → AhaType 模块
    /// - `aiHooks.isEnabled`（任一启用工具）→ AI 集成（工具状态 + 自动批准策略）
    /// - `devicePresentation.isEnabled`（LED 或 OLED）→ 动态灯效
    /// - `powerProtectionEnabled` → 防休眠
    public static func plan(for policy: AhaKeyRuntimePolicy) -> RuntimeModulePlan {
        var modules = Set<RuntimeModuleID>()
        if policy.ahaType.enabled { modules.insert(.ahaType) }
        if policy.aiHooks.isEnabled { modules.insert(.aiIntegration) }
        if policy.devicePresentation.isEnabled { modules.insert(.dynamicLighting) }
        if policy.powerProtectionEnabled { modules.insert(.powerProtection) }
        return RuntimeModulePlan(desiredModules: modules)
    }

    /// 只在事实变化时返回 transition；两次 plan 相同返回 `nil`（调用方不得发布）。
    public static func transition(
        from previous: RuntimeModulePlan,
        to next: RuntimeModulePlan
    ) -> RuntimeModuleTransition? {
        guard previous != next else { return nil }
        let started = next.desiredModules.subtracting(previous.desiredModules)
        let stopped = previous.desiredModules.subtracting(next.desiredModules)
        let residency: Bool? =
            previous.shouldStayResident == next.shouldStayResident
            ? nil
            : next.shouldStayResident
        return RuntimeModuleTransition(started: started, stopped: stopped, residencyChanged: residency)
    }
}
