import Foundation

// MARK: - 设备命令序列化与 waiter 归属（WBS-5.5 切片 1）
//
// Runtime 唯一设备所有权的核心纯逻辑：串行命令队列 + waiter 注册表。
// 纯值类型、无 CoreBluetooth 依赖，供 Agent/Runtime 设备模块驱动真实 transport。
//
// 不变量（对应任务卡完成定义）：
// - 命令严格串行：同一时刻最多一个在途命令（head-of-line）。
// - waiter 五元绑定：operation / device / session generation / transport generation / request。
// - 迟到回包不得完成新 generation 的 waiter：generation 任何分量不一致即判迟到。
// - 断连 = generation 更迭：旧 generation waiter 全部失败，绝不携带到新 generation。

/// 设备身份：稳定 device ID（跨重连不变，取广播设备编号/序列号）+ 连接级 generation。
public struct DeviceIdentity: Equatable, Hashable {
    /// 稳定设备 ID（广播 4 位编号或序列号推导），未识别时不能用 waiter。
    public let deviceID: String
    public init(deviceID: String) { self.deviceID = deviceID }
}

/// 连接代际。session = 设备模块启动一次；transport = 单次 BLE/USB 连接。
public struct DeviceGenerations: Equatable, Hashable {
    public let session: UInt64
    public let transport: UInt64
    public init(session: UInt64, transport: UInt64) {
        self.session = session
        self.transport = transport
    }
}

/// 单条串行命令。
public struct DeviceCommand: Equatable {
    public let operationID: UInt64
    public let deviceID: String
    public let generations: DeviceGenerations
    public let opcode: UInt8
    public let payload: Data
    public init(operationID: UInt64, deviceID: String, generations: DeviceGenerations, opcode: UInt8, payload: Data) {
        self.operationID = operationID
        self.deviceID = deviceID
        self.generations = generations
        self.opcode = opcode
        self.payload = payload
    }
}

/// 串行命令队列：FIFO，head 在途，完成后才放行下一条。
public struct DeviceCommandQueue {
    public private(set) var pending: [DeviceCommand] = []
    public private(set) var inFlight: DeviceCommand? = nil

    public init() {}

    /// 入队。若当前无在途命令，返回应立即下发的命令（新 head）。
    @discardableResult
    public mutating func enqueue(_ cmd: DeviceCommand) -> DeviceCommand? {
        pending.append(cmd)
        return promoteIfIdle()
    }

    /// head 完成（成功/失败/超时均走这里）。返回新放行的下一条命令（若有）。
    @discardableResult
    public mutating func completeHead() -> DeviceCommand? {
        inFlight = nil
        if !pending.isEmpty { pending.removeFirst() }
        return promoteIfIdle()
    }

    /// 断连/代际失效：清空全部队列与在途。
    public mutating func invalidateAll() {
        pending.removeAll()
        inFlight = nil
    }

    private mutating func promoteIfIdle() -> DeviceCommand? {
        guard inFlight == nil, let head = pending.first else { return nil }
        inFlight = head
        return head
    }
}

/// waiter 完成结果。
public enum DeviceWaiterOutcome: Equatable {
    case response(Data)
    case timedOut
    case generationInvalidated  // 断连/换 transport：旧代际强制失败
    case superseded             // 同 operation 被更新请求取代（预留，当前不主动产生）
}

/// 一个等待回包的 waiter。
public struct DeviceWaiter: Equatable {
    public let operationID: UInt64
    public let deviceID: String
    public let generations: DeviceGenerations
    public let requestID: UInt64
    public let deadline: Date
    public init(operationID: UInt64, deviceID: String, generations: DeviceGenerations, requestID: UInt64, deadline: Date) {
        self.operationID = operationID
        self.deviceID = deviceID
        self.generations = generations
        self.requestID = requestID
        self.deadline = deadline
    }
}

/// waiter 注册表。回包路由的唯一入口。
public struct DeviceWaiterRegistry {
    /// requestID → waiter
    public private(set) var waiters: [UInt64: DeviceWaiter] = [:]
    private var nextRequestID: UInt64 = 0

    public init() {}

    /// 注册 waiter，返回分配的 requestID。
    public mutating func register(
        operationID: UInt64,
        deviceID: String,
        generations: DeviceGenerations,
        now: Date,
        timeout: TimeInterval
    ) -> UInt64 {
        nextRequestID &+= 1
        let id = nextRequestID
        waiters[id] = DeviceWaiter(
            operationID: operationID,
            deviceID: deviceID,
            generations: generations,
            requestID: id,
            deadline: now.addingTimeInterval(timeout)
        )
        return id
    }

    /// 回包到达。只有五元绑定全部匹配才完成；任何一项不符都视为迟到/串台回包，
    /// 返回 nil——绝不完成新 generation 的 waiter。
    /// 调用方负责先验明回包属于哪个 requestID（协议序号或 FIFO head 对应）。
    @discardableResult
    public mutating func resolve(
        requestID: UInt64,
        fromOperation operationID: UInt64,
        device deviceID: String,
        generations: DeviceGenerations,
        payload: Data
    ) -> DeviceWaiterOutcome? {
        guard let w = waiters[requestID] else { return nil }
        guard w.operationID == operationID,
              w.deviceID == deviceID,
              w.generations == generations else {
            return nil  // 迟到回包：不完成、不删除——由超时或 generationInvalidated 收尾
        }
        waiters.removeValue(forKey: requestID)
        return .response(payload)
    }

    /// 收集超时 waiter 并移除，返回它们的 outcome 列表（requestID 有序）。
    public mutating func collectTimeouts(now: Date) -> [(requestID: UInt64, outcome: DeviceWaiterOutcome)] {
        let expired = waiters.filter { $0.value.deadline <= now }.map { $0.key }.sorted()
        guard !expired.isEmpty else { return [] }
        return expired.map { id in
            waiters.removeValue(forKey: id)
            return (id, .timedOut)
        }
    }

    /// 断连/失效：强败**全部** waiter（含当前代际——transport 已消失，无人能给它们回包）。
    @discardableResult
    public mutating func invalidateAll() -> [(requestID: UInt64, outcome: DeviceWaiterOutcome)] {
        let all = waiters.keys.sorted()
        guard !all.isEmpty else { return [] }
        return all.map { id in
            waiters.removeValue(forKey: id)
            return (id, .generationInvalidated)
        }
    }

    /// 代际失效（断连/重连）：移除所有绑定旧代际的 waiter。
    /// 返回被强败的 waiter（requestID 有序）。绑定新代际的不受影响。
    @discardableResult
    public mutating func invalidateGenerations(
        notMatching current: DeviceGenerations
    ) -> [(requestID: UInt64, outcome: DeviceWaiterOutcome)] {
        let stale = waiters.filter { $0.value.generations != current }.map { $0.key }.sorted()
        guard !stale.isEmpty else { return [] }
        return stale.map { id in
            waiters.removeValue(forKey: id)
            return (id, .generationInvalidated)
        }
    }

    public var isEmpty: Bool { waiters.isEmpty }
}
