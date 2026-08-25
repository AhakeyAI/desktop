import Foundation

// MARK: - 设备 transport 生命周期核心（WBS-5.5 切片 2）
//
// 连接生命周期状态机：CoreBluetooth/USB 细节全部留在 channel 适配层，
// 本核心只决策「何时扫描、连谁、何时协商、何时 ready、断连后怎么办」。
//
// 不变量：
// - current-only：0x99 协商结果必须 .current 才进入 ready；legacy/unknown 不 ready。
// - 每次成功连接 transport generation +1；断连强败旧代际 waiter、清空命令队列。
// - 断连重连走 BackoffSchedule；上电/显式请求 reset 退避。
// - RSSI/诊断不进本核心（DeviceStateReducer 已隔离），本核心只产生核心投影相关事件。

/// transport 生命周期。
public enum DeviceTransportPhase: Equatable {
    case idle                 // 未启动或蓝牙未就绪
    case awaitingLock         // 想连接但跨进程锁被占
    case scanning
    case connecting(uuid: String)
    case discovering(uuid: String)
    case negotiating(uuid: String)
    case ready(uuid: String, deviceID: String)
    case backoffReconnect(until: Date)
}

/// channel 适配层必须落地的动作（CoreBluetooth/USB 各一份实现）。
public enum DeviceTransportAction: Equatable {
    case acquireConnectionLock
    case scan
    case connectKnown(uuid: String)
    case connectSystemAttached
    case discoverServices(uuid: String)
    case sendCapabilityNegotiation(uuid: String)
    case disconnect(uuid: String)
    /// 到点重连（由调度层在 after 之后回调 `reconnectTimerFired`）。
    case scheduleReconnectTimer(after: TimeInterval)
}

/// 注入核心的事件。
public enum DeviceTransportEvent {
    case bluetoothPoweredOn
    case bluetoothUnavailable
    case lockAcquired
    case lockBusy
    case knownDeviceFound(uuid: String)
    case systemAttachedDeviceFound(uuid: String)
    case discovered(uuid: String, deviceID: String?)
    case connected(uuid: String)
    case servicesReady(uuid: String)
    /// 0x99 协商终态。
    case negotiationFinished(uuid: String, mode: AhaKeyProtocolMode)
    case disconnected(uuid: String)
    case reconnectTimerFired
}

public struct DeviceTransportCore {
    public private(set) var phase: DeviceTransportPhase = .idle
    public private(set) var generations: DeviceGenerations
    /// 稳定 device ID（ready 后可用；来自广播编号/序列号）。
    public private(set) var stableDeviceID: String? = nil
    /// 上次连接的 UUID（断连重连优先直连）。
    public private(set) var lastUUID: String? = nil
    public private(set) var backoff: BackoffSchedule
    public private(set) var commandQueue = DeviceCommandQueue()
    public private(set) var waiters = DeviceWaiterRegistry()
    private let sessionGeneration: UInt64
    private var transportGeneration: UInt64 = 0

    public init(sessionGeneration: UInt64, backoff: BackoffSchedule = BackoffSchedule()) {
        self.sessionGeneration = sessionGeneration
        self.generations = DeviceGenerations(session: sessionGeneration, transport: 0)
        self.backoff = backoff
    }

    /// 当前代际（供发送命令/注册 waiter 使用）。
    public var currentGenerations: DeviceGenerations { generations }

    /// 是否可下发业务命令（current-only 门在这里生效）。
    public var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    @discardableResult
    public mutating func handle(_ event: DeviceTransportEvent, now: Date) -> [DeviceTransportAction] {
        switch event {
        case .bluetoothPoweredOn:
            backoff.reset()
            phase = .awaitingLock
            return [.acquireConnectionLock]

        case .bluetoothUnavailable:
            let invalidated = invalidateTransport()
            phase = .idle
            return invalidated

        case .lockAcquired:
            guard case .awaitingLock = phase else { return [] }
            return startConnecting()

        case .lockBusy:
            // 锁被占：保持 awaitingLock，靠 channel 层低频重试（不刷日志）。
            phase = .awaitingLock
            return []

        case let .knownDeviceFound(uuid):
            phase = .connecting(uuid: uuid)
            return [.connectKnown(uuid: uuid)]

        case let .systemAttachedDeviceFound(uuid):
            phase = .connecting(uuid: uuid)
            return [.connectSystemAttached]

        case let .discovered(uuid, deviceID):
            if let deviceID { stableDeviceID = deviceID }
            phase = .connecting(uuid: uuid)
            return [.connectKnown(uuid: uuid)]

        case let .connected(uuid):
            transportGeneration &+= 1
            generations = DeviceGenerations(session: sessionGeneration, transport: transportGeneration)
            lastUUID = uuid
            phase = .discovering(uuid: uuid)
            return [.discoverServices(uuid: uuid)]

        case let .servicesReady(uuid):
            guard case .discovering = phase else { return [] }
            phase = .negotiating(uuid: uuid)
            return [.sendCapabilityNegotiation(uuid: uuid)]

        case let .negotiationFinished(uuid, mode):
            guard case .negotiating = phase else { return [] }
            guard mode == .current else {
                // current-only：不 ready、不断连（保留诊断通道），等待外部策略。
                return []
            }
            let deviceID = stableDeviceID ?? uuid
            stableDeviceID = deviceID
            phase = .ready(uuid: uuid, deviceID: deviceID)
            return []

        case let .disconnected(uuid):
            var actions = invalidateTransport()
            lastUUID = uuid
            let delay = backoff.next()
            phase = .backoffReconnect(until: now.addingTimeInterval(delay))
            actions.append(.scheduleReconnectTimer(after: delay))
            return actions

        case .reconnectTimerFired:
            guard case .backoffReconnect = phase else { return [] }
            phase = .awaitingLock
            return [.acquireConnectionLock]
        }
    }

    /// 连接偏好顺序：已知 UUID → 系统已连接 → 扫描。
    private mutating func startConnecting() -> [DeviceTransportAction] {
        if let uuid = lastUUID {
            phase = .connecting(uuid: uuid)
            return [.connectKnown(uuid: uuid)]
        }
        phase = .scanning
        return [.scan]
    }

    /// 断连/失效公共收尾：强败旧代际 waiter、清队列。
    private mutating func invalidateTransport() -> [DeviceTransportAction] {
        _ = waiters.invalidateGenerations(notMatching: generations)
        commandQueue.invalidateAll()
        return []
    }
}
