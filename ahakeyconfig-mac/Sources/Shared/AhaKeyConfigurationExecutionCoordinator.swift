import Foundation

// MARK: - 配置事务串行执行协调器（WBS-5.7 R2 收口）
//
// 问题背景：此前每次 durable accept 都新建一个执行 Task，遇到单飞闸门占用直接
// busy 退出，后受理的事务滞留 WAL 直到下次重连；多个 XPC session 又可并发读写
// 非隔离的执行入口。本协调器把执行收敛为 Agent 自有、单一 actor 隔离的串行 worker：
//
// - 所有 durable accepted 事务经 `kick()` 登记；worker 按 WAL 顺序持续排空
//   （前一个事务执行完成后自动取下一个，含执行期间新受理的事务）。
// - 任一时刻至多一个 worker Task；kick 绝不覆盖在途 worker；
//   同一 worker 内顺序 await，天然杜绝两个 BLE runner 并行。
// - 多 XPC session 并发 kick 由 actor 隔离串行化，无共享可变标志。
//
// 事务的 WAL 推进/终态/事件发布由注入的执行体负责；执行体必须自行兜住错误不抛出
// （失败事务留在 WAL，由后续 kick/重连恢复，worker 不空转重试）。

public actor AhaKeyConfigurationExecutionCoordinator {
    /// 拉取 WAL 待执行候选包（按受理序；取消请求中/终态由提供方过滤）。
    public typealias PendingPackagesProvider = @Sendable () async -> [AhaKeyConfigurationPackage]
    /// 执行单个事务（必须兜住全部错误、不抛出）。
    public typealias ExecutePackage = @Sendable (AhaKeyConfigurationPackage) async -> Void

    private let pendingPackagesProvider: PendingPackagesProvider
    private let executePackage: ExecutePackage
    /// 在途 worker（至多一个；nil = 空闲）。
    private var worker: Task<Void, Never>?
    /// worker 运行期间到达的 kick 记为 pending，本趟排空后再跑一趟。
    private var kickWhileRunning = false

    public init(
        pendingPackages: @escaping PendingPackagesProvider,
        executePackage: @escaping ExecutePackage
    ) {
        self.pendingPackagesProvider = pendingPackages
        self.executePackage = executePackage
    }

    /// durable accept / 连接 ready / 恢复触发点的统一入口。幂等；不覆盖在途 worker。
    public func kick() {
        if worker != nil {
            kickWhileRunning = true
            return
        }
        startWorker()
    }

    /// 测试观察：当前是否有在途 worker。
    public var hasActiveWorker: Bool { worker != nil }

    private func startWorker() {
        worker = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// worker 主循环：每趟先清 pending 标记再排空 WAL；趟间到达的 kick 触发下一趟。
    /// `guard` 判定与 `worker = nil` 之间无挂起点（actor 隔离），kick 不会丢失。
    private func runLoop() async {
        while true {
            kickWhileRunning = false
            let pending = await pendingPackagesProvider()
            for package in pending {
                await executePackage(package)
            }
            guard kickWhileRunning else { break }
        }
        worker = nil
    }
}
