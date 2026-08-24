import Foundation

/// 模块生命周期注册表。
///
/// 职责：
/// 1. 维护 `RuntimeModuleID → RuntimeModule` 映射；
/// 2. 按 `RuntimeModuleTransition` 并行启动/停止模块；
/// 3. **错误隔离**：单个模块 start/stop 失败只标记该模块为 `.failed`，不影响其他模块。
///
/// 线程安全：内部状态由 `actor` 隔离；外部调用一律 `await`。
public actor RuntimeModuleRegistry {
    private var modules: [RuntimeModuleID: any RuntimeModule] = [:]
    private var statuses: [RuntimeModuleID: RuntimeModuleStatus] = [:]

    public init() {}

    /// 注册模块。同一 ID 重复注册覆盖（用于测试/fixture）。
    public func register(_ module: any RuntimeModule) {
        modules[module.id] = module
        if statuses[module.id] == nil {
            statuses[module.id] = .idle
        }
    }

    /// 注销模块。若模块正在运行，先 stop。
    public func unregister(_ id: RuntimeModuleID) async {
        if let module = modules[id], await module.status == .running {
            await module.stop()
        }
        modules.removeValue(forKey: id)
        statuses.removeValue(forKey: id)
    }

    /// 当前所有模块状态快照。
    public func snapshot() -> [RuntimeModuleID: RuntimeModuleStatus] {
        statuses
    }

    /// 按 transition 执行并行启动与停止。
    ///
    /// - 启动：并行 `await module.start()`，失败仅标记该模块 `.failed`。
    /// - 停止：并行 `await module.stop()`，失败仅标记 `.failed`（不抛）。
    /// - 返回值：所有发生状态变更的模块 ID 集合（无论成功/失败）。
    @discardableResult
    public func applyTransition(_ transition: RuntimeModuleTransition) async -> Set<RuntimeModuleID> {
        var changed = Set<RuntimeModuleID>()

        // 1. 并行启动
        await withTaskGroup(of: (RuntimeModuleID, Result<Void, Error>).self) { group in
            for id in transition.started {
                guard let module = modules[id] else { continue }
                group.addTask {
                    do {
                        try await module.start()
                        return (id, .success(()))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }

            for await (id, result) in group {
                switch result {
                case .success:
                    statuses[id] = .running
                case .failure(let error):
                    let message = (error as? RuntimeModuleError)?.localizedDescription ?? String(describing: error)
                    statuses[id] = .failed(.startFailed(module: id, underlying: message))
                }
                changed.insert(id)
            }
        }

        // 2. 并行停止（stop 不抛出，失败由模块经自身 status 上报）
        await withTaskGroup(of: (RuntimeModuleID, RuntimeModuleStatus).self) { group in
            for id in transition.stopped {
                guard let module = modules[id] else { continue }
                group.addTask {
                    await module.stop()
                    return (id, module.status)
                }
            }

            for await (id, moduleStatus) in group {
                if case .failed = moduleStatus {
                    statuses[id] = moduleStatus
                } else {
                    statuses[id] = .idle
                }
                changed.insert(id)
            }
        }

        return changed
    }

    /// 查询单个模块状态。
    public func status(of id: RuntimeModuleID) -> RuntimeModuleStatus {
        statuses[id] ?? .idle
    }

    /// 强制停止所有已注册模块（用于进程退出清理）。
    public func stopAll() async {
        await withTaskGroup(of: Void.self) { group in
            for (_, module) in modules {
                group.addTask {
                    await module.stop()
                }
            }
        }
        for id in modules.keys {
            statuses[id] = .idle
        }
    }
}
