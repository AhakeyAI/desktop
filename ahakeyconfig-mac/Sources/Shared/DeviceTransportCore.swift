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
    /// 连接失败后继续 BLE 扫描，不再立刻 retrieve（避免同栈对同一快照死循环）。
    case resumeScanning
    case connectKnown(uuid: String)
    case connectSystemAttached(uuid: String)
    case discoverServices(uuid: String)
    case sendCapabilityNegotiation(uuid: String)
    case disconnect(uuid: String)
    /// 到点重连（由调度层在 after 之后回调 `reconnectTimerFired`）。
    case scheduleReconnectTimer(after: TimeInterval)
    /// 扫描期低频重查系统已连 HID（适配层到点回调 `systemAttachedProbeFired`）。
    case scheduleSystemAttachedProbe(after: TimeInterval, token: UInt64)
    /// 作废适配层尚未触发的 probe timer。
    case cancelSystemAttachedProbe
    /// 适配层此刻调用 `retrieveConnectedPeripherals`；空结果回 `systemAttachedProbeEmpty`。
    case probeSystemAttached
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
    /// 连接后补充设备身份（已知 UUID/系统已连路径没有广播包，用设备名后缀/2A25 序列号）。
    case deviceIdentified(deviceID: String)
    case disconnected(uuid: String)
    case reconnectTimerFired
    /// 适配层 probe timer 到点。token 过期或非 scanning 必须 no-op。
    case systemAttachedProbeFired(token: UInt64)
    /// `retrieveConnectedPeripherals` 空结果。scanning 期只重排一次下一发 probe。
    case systemAttachedProbeEmpty
    /// 进程/适配器关闭：作废 waiter、probe token，phase → idle。过期 timer 不得再连。
    case shutdown
    /// 携带的 system-attached 外设在 connect 前消失，或 `connect` 未能启动。
    /// connecting 必须回到 scanning 并恰重排一次 probe。
    case lookupOrConnectFailed
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
    /// 协商完成但身份未识别时暂存 mode，等 deviceIdentified 补齐后落 ready。
    private var pendingNegotiatedMode: AhaKeyProtocolMode? = nil
    /// 扫描期 system-attached probe 代际；离开 scanning / 蓝牙不可用时递增，过期 timer 不得再连。
    public private(set) var systemAttachedProbeToken: UInt64 = 0
    public static let systemAttachedProbeInterval: TimeInterval = 1.5

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
            var actions = invalidateTransport()
            actions.append(contentsOf: invalidateSystemAttachedProbe())
            phase = .idle
            return actions

        case .lockAcquired:
            guard case .awaitingLock = phase else { return [] }
            return startConnecting()

        case .lockBusy:
            // 锁被占：保持 awaitingLock，靠 channel 层低频重试（不刷日志）。
            phase = .awaitingLock
            return []

        case let .knownDeviceFound(uuid):
            guard case .scanning = phase else { return [] }
            var actions = invalidateSystemAttachedProbe()
            phase = .connecting(uuid: uuid)
            actions.append(.connectKnown(uuid: uuid))
            return actions

        case let .systemAttachedDeviceFound(uuid):
            guard case .scanning = phase else { return [] }
            var actions = invalidateSystemAttachedProbe()
            phase = .connecting(uuid: uuid)
            actions.append(.connectSystemAttached(uuid: uuid))
            return actions

        case let .discovered(uuid, deviceID):
            if let deviceID { stableDeviceID = deviceID }
            var actions = invalidateSystemAttachedProbe()
            phase = .connecting(uuid: uuid)
            actions.append(.connectKnown(uuid: uuid))
            return actions

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

        case let .negotiationFinished(uuid, mode):            guard case .negotiating = phase else { return [] }
            guard mode == .current else {
                // current-only：不 ready、不断连（保留诊断通道），等待外部策略。
                return []
            }
            // 稳定 device ID 必须来自广播编号/序列号；未识别时暂存 mode，等身份补齐再落 ready。
            guard let deviceID = stableDeviceID else {
                pendingNegotiatedMode = mode
                return []
            }
            phase = .ready(uuid: uuid, deviceID: deviceID)
            return []

        case let .deviceIdentified(deviceID):
            if stableDeviceID == nil { stableDeviceID = deviceID }
            // 身份补齐：若协商已在等身份，落 ready
            if let mode = pendingNegotiatedMode, mode == .current,
               case .negotiating(let uuid) = phase {
                pendingNegotiatedMode = nil
                phase = .ready(uuid: uuid, deviceID: deviceID)
            }
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

        case let .systemAttachedProbeFired(token):
            guard token == systemAttachedProbeToken, case .scanning = phase else { return [] }
            return [.probeSystemAttached]

        case .systemAttachedProbeEmpty:
            guard case .scanning = phase else { return [] }
            return [armSystemAttachedProbe()]

        case .shutdown:
            var actions = invalidateTransport()
            actions.append(contentsOf: invalidateSystemAttachedProbe())
            phase = .idle
            return actions

        case .lookupOrConnectFailed:
            guard case .connecting = phase else { return [] }
            phase = .scanning
            return [.resumeScanning, armSystemAttachedProbe()]
        }
    }

    /// 连接偏好顺序：已知 UUID → 系统已连接 → 扫描。
    private mutating func startConnecting() -> [DeviceTransportAction] {
        if let uuid = lastUUID {
            phase = .connecting(uuid: uuid)
            return [.connectKnown(uuid: uuid)]
        }
        phase = .scanning
        return [.scan, armSystemAttachedProbe()]
    }

    private mutating func armSystemAttachedProbe() -> DeviceTransportAction {
        systemAttachedProbeToken &+= 1
        return .scheduleSystemAttachedProbe(
            after: Self.systemAttachedProbeInterval,
            token: systemAttachedProbeToken
        )
    }

    private mutating func invalidateSystemAttachedProbe() -> [DeviceTransportAction] {
        systemAttachedProbeToken &+= 1
        return [.cancelSystemAttachedProbe]
    }

    /// 断连/失效公共收尾：强败全部 waiter（含当前代际）、清队列。
    private mutating func invalidateTransport() -> [DeviceTransportAction] {
        _ = waiters.invalidateAll()
        commandQueue.invalidateAll()
        return []
    }

    // MARK: - 命令/waiter 生产路径封装（Agent/Runtime 使用，不允许绕过）

    /// 入队命令；返回应立即下发的 head（若此前空闲）。
    @discardableResult
    public mutating func enqueue(_ cmd: DeviceCommand) -> DeviceCommand? {
        commandQueue.enqueue(cmd)
    }

    /// head 完成，返回新放行的命令。
    @discardableResult
    public mutating func completeHeadCommand() -> DeviceCommand? {
        commandQueue.completeHead()
    }

    public var inFlightCommand: DeviceCommand? { commandQueue.inFlight }

    /// 注册绑定当前代际的 waiter，返回 requestID。
    public mutating func registerWaiter(operationID: UInt64, now: Date, timeout: TimeInterval) -> UInt64? {
        guard let deviceID = stableDeviceID else { return nil }  // 未识别设备身份不注册 waiter
        return waiters.register(operationID: operationID, deviceID: deviceID,
                                generations: generations, now: now, timeout: timeout)
    }

    /// 回包路由：五元匹配才完成；迟到回包返回 nil。
    @discardableResult
    public mutating func resolveWaiter(requestID: UInt64, operationID: UInt64, payload: Data) -> DeviceWaiterOutcome? {
        guard let deviceID = stableDeviceID else { return nil }
        return waiters.resolve(requestID: requestID, fromOperation: operationID,
                               device: deviceID, generations: generations, payload: payload)
    }

    /// 收集超时 waiter。
    public mutating func collectWaiterTimeouts(now: Date) -> [(requestID: UInt64, outcome: DeviceWaiterOutcome)] {
        waiters.collectTimeouts(now: now)
    }
}
