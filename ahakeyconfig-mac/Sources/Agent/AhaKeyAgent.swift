import CoreBluetooth
import Foundation
import os.log

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig.agent", category: "BLE")

/// 设备 8 字节状态解析结果。
///
/// 与 Sources/BLE/AhaKeyProtocol.swift 的 `AhaKeyDeviceStatus` 保持同构；
/// Agent 是独立 target，不共享源码，所以这里内联一份极简解析器。
struct AgentDeviceStatus {
    let battery: Int
    let signal: Int
    let firmwareMain: Int
    let firmwareSub: Int
    let workMode: Int
    let lightMode: Int
    let switchState: Int
}

/// 轻量 BLE 守护进程：维持连接 + 接收 Unix socket 命令 → 发送 LED 状态 / 回传拨杆状态
final class AhaKeyAgent: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var lastUUID: UUID?
    private let serviceUUID = CBUUID(string: "7340")
    private let commandCharUUID = CBUUID(string: "7343")
    private let notifyCharUUID = CBUUID(string: "7344")
    private let deviceNamePrefix = "AhaKey"
    private let socketPath: String

    private let header: [UInt8] = [0xAA, 0xBB]
    private let trailer: [UInt8] = [0xCC, 0xDD]

    // MARK: 缓存（供 hook 查询使用）
    /// 最新 switchState（0=auto, 1=manual），未知时 nil
    private(set) var cachedSwitchState: UInt8?
    /// 最新 lightMode
    private(set) var cachedLightMode: UInt8?
    /// 用户在画布点击虚拟拨杆设置的覆盖值；非 nil 时优先于 cachedSwitchState 用于 hook auto-approve 判断。
    /// 持久化到 UserDefaults 以便 agent 重启后保留。物理拨杆损坏的用户靠这个让 hook 自动批准生效。
    private(set) var userSwitchOverride: UInt8?

    private static let switchOverrideDefaultsKey = "lab.jawa.ahakeyconfig.agent.userSwitchOverride"

    /// 等待下一次 status 回包的回调队列（用于 querySwitchState）
    private var statusWaiters: [(AgentDeviceStatus?) -> Void] = []
    /// 工具完成 / 用户提交等短暂态的自动回落。
    private var pendingStateReset: DispatchWorkItem?

    // MARK: 看门狗（Claude Code 手动停止任务时 Stop hook 不触发，超时后自动归位）
    /// 最近一次 hook 发来状态命令的时间（nil = 尚未收到）
    private var lastHookStateAt: Date?
    /// 最近一次我们主动发给键盘的 LED 状态
    private var lastSentState: UInt8 = 0
    private var watchdogTimer: DispatchSourceTimer?

    /// 各活跃态超时时长（秒）：
    ///   1=PermissionRequest / 7=UserPromptSubmit → 30s（等待阶段，手动停止后无 hook 跟进）
    ///   其余工具执行态 → 60s（工具可能运行较久，避免误触发）
    private func watchdogTimeout(for state: UInt8) -> Double {
        switch state {
        case 1, 7: return 30   // PermissionRequest / UserPromptSubmit：短超时
        default:   return 60   // PreToolUse / PostToolUse / SessionStart / TaskCompleted
        }
    }

    var onLog: ((String) -> Void)?

    init(socketPath: String = AhaKeySocket.defaultPath) {
        self.socketPath = socketPath
        if let raw = UserDefaults.standard.object(forKey: Self.switchOverrideDefaultsKey) as? Int {
            userSwitchOverride = UInt8(clamping: raw)
        }
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        // 启动时如果有持久化的 override，立刻把它落进共享文件，让主 App UI 一上来就能看到
        Self.writeLiveState(switchState: userSwitchOverride)
    }

    /// 实际给 hook 用的拨杆值：用户覆盖优先，没有就回落到 BLE 缓存
    var effectiveSwitchState: UInt8? {
        userSwitchOverride ?? cachedSwitchState
    }

    func setSwitchOverride(_ value: UInt8?) {
        userSwitchOverride = value
        if let v = value {
            UserDefaults.standard.set(Int(v), forKey: Self.switchOverrideDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.switchOverrideDefaultsKey)
        }
        // 最新固件中 0x91 已用于灯效预览；拨杆只保留 hook 软件覆盖，不再向键盘发送旧 0x91。
        if let v = value {
            emit("拨杆 \(v) 仅记录为软件覆盖；不发送旧 0x91。")
        }
        // 把覆盖值写进共享文件，主 App 立刻看到画布拨杆位置更新
        Self.writeLiveState(switchState: effectiveSwitchState)
        emit("拨杆覆盖 = \(value.map { String($0) } ?? "清除")（effective=\(effectiveSwitchState.map { String($0) } ?? "未知")）")
    }

    // MARK: - Public

    func sendState(_ state: UInt8) {
        pendingStateReset?.cancel()
        pendingStateReset = nil
        guard let commandChar, let peripheral else {
            emit("LED 状态 \(state): 未连接")
            return
        }
        let data = Data(header + [0x90, state] + trailer)
        let wt: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: wt)
        lastSentState = state
        emit("→ LED 状态 \(state): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        Self.writeLiveState(stateValue: state)
    }

    /// 把 agent 当前对键盘的认知（最近一次 hook 发送的 stateValue + BLE 上报的 lightMode/switchState/workMode）
    /// merge-write 到共享文件，供主 App 在 agent 拥有 BLE 时读取实时状态。
    /// 任意调用方只传自己负责更新的字段；未传的字段保留文件中的旧值。
    static func writeLiveState(stateValue: UInt8? = nil,
                               lightMode: UInt8? = nil,
                               switchState: UInt8? = nil,
                               workMode: UInt8? = nil) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("current-ide-state.json")
        var obj: [String: Any] = [:]
        if let existing = try? Data(contentsOf: url),
           let parsed = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] {
            obj = parsed
        }
        let now = Date().timeIntervalSince1970
        if let s = stateValue {
            obj["stateValue"] = Int(s)
            obj["stateTs"] = now
        }
        if let lm = lightMode {
            obj["lightMode"] = Int(lm)
            obj["lightModeTs"] = now
        }
        if let sw = switchState {
            obj["switchState"] = Int(sw)
        }
        if let wm = workMode {
            obj["workMode"] = Int(wm)
        }
        obj["ts"] = now
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 主动查询一次设备状态，等待下一个 notify 回包 (timeout 秒内)。
    /// 超时时用缓存兜底；仍然没有则返回 nil。完成回调在 main 队列。
    func querySwitchState(timeout: TimeInterval = 1.5,
                          completion: @escaping (AgentDeviceStatus?) -> Void) {
        guard let commandChar, let peripheral else {
            completion(nil)
            return
        }
        // 发设备状态查询命令 AA BB 00 CC DD
        let query = Data(header + [0x00] + trailer)
        let wt: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(query, for: commandChar, type: wt)

        statusWaiters.append(completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            // 把目前仍在队列里的 waiter 全部用缓存兜底 fire 掉
            guard !self.statusWaiters.isEmpty else { return }
            let waiters = self.statusWaiters
            self.statusWaiters.removeAll()
            let fallback = self.cachedStatus()
            for w in waiters { w(fallback) }
        }
    }

    private func cachedStatus() -> AgentDeviceStatus? {
        guard let sw = cachedSwitchState else { return nil }
        return AgentDeviceStatus(
            battery: -1, signal: -1, firmwareMain: -1, firmwareSub: -1,
            workMode: -1, lightMode: Int(cachedLightMode ?? 0), switchState: Int(sw)
        )
    }

    @discardableResult
    func startSocketListener() -> Bool {
        if Self.hasLiveSocket(at: socketPath) {
            emit("已有 Agent 在监听 Unix socket: \(socketPath)")
            return false
        }

        startWatchdog()

        do {
            try AhaKeySocket.prepareDirectory()
        } catch {
            emit("socket 目录准备失败: \(error.localizedDescription)")
            return false
        }

        // 清理没有监听进程的残留 socket
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { emit("socket() 失败"); return false }

        guard var addr = AhaKeySocket.makeAddress(path: socketPath) else {
            emit("socket 路径超出 sockaddr_un 容量: \(socketPath)")
            close(fd)
            return false
        }

        // 权限由 bind 时的 umask 决定，事后 chmod 会留下一个宽松窗口，所以两者都做。
        let previousMask = umask(0o177)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bindResult == 0 else { emit("bind() 失败: \(errno)"); close(fd); return false }
        if chmod(socketPath, 0o600) != 0 {
            emit("chmod 0600 失败: \(errno)（socket 可能对其他用户可见）")
        }

        listen(fd, 5)
        emit("监听 Unix socket: \(socketPath)（0600，仅本用户）")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let clientFd = accept(fd, nil, nil)
                guard clientFd >= 0 else { continue }
                guard AhaKeySocket.peerIsSameUser(clientFd) else {
                    close(clientFd)
                    self?.emit("拒绝连接：对端不是本用户")
                    continue
                }
                self?.handleClient(clientFd)
            }
        }
        return true
    }

    // MARK: - 看门狗

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.checkWatchdog()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func checkWatchdog() {
        guard let lastAt = lastHookStateAt else { return }
        let activeStates: [UInt8] = [1, 2, 3, 4, 6, 7]
        guard activeStates.contains(lastSentState) else { return }
        let elapsed = Date().timeIntervalSince(lastAt)
        let threshold = watchdogTimeout(for: lastSentState)
        guard elapsed >= threshold else { return }
        emit("⏰ 看门狗：\(Int(elapsed))s 无 hook 活动（上次 LED=\(lastSentState)，阈值 \(Int(threshold))s），自动发 Stop(5)")
        sendState(5)
        lastHookStateAt = nil  // 重置，避免重复触发
    }

    // MARK: - Socket handling

    private static func hasLiveSocket(at path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        guard var addr = AhaKeySocket.makeAddress(path: path) else { return false }

        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }

    /// 单个客户端的处理：读一包请求，按 JSON 或旧版纯数字分发。
    ///
    /// 协议：
    /// - JSON 一行：`{"cmd":"state","value":3}` / `{"cmd":"permission","value":1}` / `{"cmd":"status"}`
    /// - 纯数字（兼容旧 `ahakey-state.sh`）：`3` → sendState(3)，不回包
    private func handleClient(_ clientFd: Int32) {
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = read(clientFd, &buf, buf.count)
        guard n > 0 else { close(clientFd); return }

        let line = String(bytes: buf[0 ..< Int(n)], encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // JSON 请求
        if let lineData = line.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
           let cmd = obj["cmd"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.handleJsonCommand(cmd: cmd, obj: obj, clientFd: clientFd)
            }
            return // fd 在命令 handler 里最终关闭
        }

        // 旧协议：纯数字当作 state，fire-and-forget
        if let state = UInt8(line) {
            DispatchQueue.main.async { [weak self] in self?.sendState(state) }
        }
        close(clientFd)
    }

    /// 在主队列执行的 JSON 命令分发。回包由 `replyAndClose` 负责异步写入 + 关 fd。
    private func handleJsonCommand(cmd: String, obj: [String: Any], clientFd: Int32) {
        switch cmd {
        case "state":
            if let v = obj["value"] as? Int {
                lastHookStateAt = Date()
                sendState(UInt8(clamping: v))
            }
            Self.replyAndClose(clientFd, ["ok": true])

        case "state_with_reset":
            let stateValue = obj["value"] as? Int ?? 0
            let resetValue = obj["resetValue"] as? Int ?? 4
            let delayMs = max(0, obj["delayMs"] as? Int ?? 1200)
            sendState(UInt8(clamping: stateValue))
            scheduleStateReset(
                to: UInt8(clamping: resetValue),
                afterMs: delayMs,
                reason: "temporary state \(stateValue) -> reset \(resetValue)"
            )
            Self.replyAndClose(clientFd, ["ok": true])

        case "permission":
            // 发 PermissionRequest 对应的 state（默认 1），同时主动查询拨杆
            let stateValue = obj["value"] as? Int ?? 1
            lastHookStateAt = Date()
            sendState(UInt8(clamping: stateValue))
            querySwitchState(timeout: 1.5) { status in
                let body = Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode)
                self.emit("← permission 回包 switchState=\(String(describing: body["switchState"]))")
                if let s = body["switchState"] as? Int, s != 0 {
                    self.emit("（拨杆非 0：PermissionRequest 将交回终端手动确认）")
                } else if body["switchState"] is NSNull {
                    self.emit("（switchState 缺省：批准链可能仍交回手动；请把「蓝牙」交给 Agent 并连上键盘。）")
                }
                Self.replyAndClose(clientFd, body)
            }

        case "status":
            // 判断 BLE 是否真实连上键盘：只有当 cachedSwitchState 不为 nil 时（键盘通过 notify 上报过）才算连上。
            // effectiveSwitchState 在用户设置了 userSwitchOverride 时即使未连上 BLE 也有值，不能作为连上键盘的依据。
            if cachedSwitchState != nil {
                Self.replyAndClose(clientFd, [
                    "switchState": effectiveSwitchState.map { Int($0) } ?? NSNull(),
                    "lightMode": cachedLightMode.map { Int($0) } ?? NSNull(),
                ])
            } else {
                querySwitchState(timeout: 1.5) { status in
                    Self.replyAndClose(clientFd, Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode))
                }
            }

        case "approval_status":
            // 给 Kimi CLI 的实时批准判断用：每次都主动向设备要当前拨杆，避免会话内沿用旧的 yolo/state。
            querySwitchState(timeout: 1.5) { status in
                Self.replyAndClose(clientFd, Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode))
            }

        case "set_switch_override":
            // 主 App 画布虚拟拨杆点击 → 设置 / 清除覆盖
            // value=null / 缺省 → 清除（恢复用真实 BLE 上报）
            // value=0/1/2 → 设置覆盖值；不再发送旧 0x91
            if obj["value"] is NSNull || obj["value"] == nil {
                setSwitchOverride(nil)
            } else if let v = obj["value"] as? Int {
                setSwitchOverride(UInt8(clamping: v))
            }
            Self.replyAndClose(clientFd, [
                "ok": true,
                "switchState": effectiveSwitchState.map { Int($0) } ?? NSNull(),
                "override": userSwitchOverride.map { Int($0) } ?? NSNull(),
            ])

        default:
            Self.replyAndClose(clientFd, ["error": "unknown cmd: \(cmd)"])
        }
    }

    private static func statusReply(_ status: AgentDeviceStatus?,
                                    cachedSwitch: UInt8?,
                                    cachedLight: UInt8?) -> [String: Any] {
        if let s = status {
            return ["switchState": s.switchState, "lightMode": s.lightMode]
        }
        return [
            "switchState": cachedSwitch.map { Int($0) } ?? NSNull(),
            "lightMode": cachedLight.map { Int($0) } ?? NSNull(),
        ]
    }

    private func scheduleStateReset(to state: UInt8, afterMs: Int, reason: String) {
        pendingStateReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sendState(state)
            self.emit("自动回落灯态：\(reason)")
        }
        pendingStateReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(afterMs), execute: work)
    }

    private static func replyAndClose(_ fd: Int32, _ dict: [String: Any]) {
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                var out = data
                out.append(0x0A) // \n 作为消息边界
                _ = out.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return -1 }
                    return write(fd, base, ptr.count)
                }
            }
            close(fd)
        }
    }

    // MARK: - Connection

    private func connectAutomatically() {
        // 1. 用已知 UUID
        if let uuid = lastUUID {
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let p = known.first {
                emit("直连已知设备: \(uuid.uuidString.prefix(8))…")
                peripheral = p
                p.delegate = self
                central.connect(p, options: nil)
                return
            }
        }

        // 2. 系统已连接
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let p = connected.first(where: { ($0.name ?? "").lowercased().hasPrefix(deviceNamePrefix.lowercased()) }) {
            emit("系统已连接: \(p.name ?? "?")")
            peripheral = p
            p.delegate = self
            central.connect(p, options: nil)
            return
        }

        // 3. 扫描
        emit("开始扫描…")
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func emit(_ msg: String) {
        log.info("\(msg)")
        onLog?(msg)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            emit("蓝牙就绪")
            connectAutomatically()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.lowercased().hasPrefix(deviceNamePrefix.lowercased()) else { return }
        central.stopScan()
        emit("发现: \(name)")
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lastUUID = peripheral.identifier
        emit("已连接: \(peripheral.name ?? "?")")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        commandChar = nil
        notifyChar = nil
        self.peripheral = nil
        cachedSwitchState = nil
        cachedLightMode = nil
        // 把 pending 的 waiter 全部通知为 nil（避免 hook 客户端一直等）
        if !statusWaiters.isEmpty {
            let waiters = statusWaiters
            statusWaiters.removeAll()
            for w in waiters { w(nil) }
        }
        emit("已断开，2s 后重连")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connectAutomatically()
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([commandCharUUID, notifyCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == commandCharUUID {
                commandChar = char
                emit("命令通道就绪")
            } else if char.uuid == notifyCharUUID {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
                emit("通知通道已订阅")
            }
        }
        // 两个特征都就绪后发一次初始状态查询
        if commandChar != nil, notifyChar != nil {
            let query = Data(header + [0x00] + trailer)
            let wt: CBCharacteristicWriteType =
                commandChar!.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(query, for: commandChar!, type: wt)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == commandCharUUID || characteristic.uuid == notifyCharUUID,
              let data = characteristic.value else { return }
        guard let status = Self.parseDeviceStatus(data) else { return }

        cachedSwitchState = UInt8(clamping: status.switchState)
        cachedLightMode = UInt8(clamping: status.lightMode)
        emit("← status battery=\(status.battery) light=\(status.lightMode) switch=\(status.switchState)")
        // 写共享文件时优先使用用户覆盖值，否则用键盘真实上报。这样主 App 画布上的拨杆位置始终与
        // hook 实际使用的批准逻辑一致（避免画布显示一档、hook 按另一档运行的割裂）。
        Self.writeLiveState(
            lightMode: UInt8(clamping: status.lightMode),
            switchState: effectiveSwitchState,
            workMode: UInt8(clamping: max(0, status.workMode))
        )

        guard !statusWaiters.isEmpty else { return }
        let waiters = statusWaiters
        statusWaiters.removeAll()
        for w in waiters { w(status) }
    }

    // MARK: - 协议内联解析

    /// 解析 AA BB 00 [battery][signal][fw_main][fw_sub][work][light][switch][reserve] CC DD
    /// 与 Sources/BLE/AhaKeyProtocol.swift:parseDeviceStatus 等价
    private static func parseDeviceStatus(_ data: Data) -> AgentDeviceStatus? {
        guard data.count >= 12,
              data[0] == 0xAA, data[1] == 0xBB,
              data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD else {
            return nil
        }
        let payload = data[2 ..< data.count - 2]
        guard payload.count >= 8, payload[payload.startIndex] == 0x00 else { return nil }
        let base = payload.startIndex + 1 // 跳过 cmd echo
        return AgentDeviceStatus(
            battery: Int(payload[base]),
            signal: Int(Int8(bitPattern: payload[base + 1])),
            firmwareMain: Int(payload[base + 2]),
            firmwareSub: Int(payload[base + 3]),
            workMode: Int(payload[base + 4]),
            lightMode: Int(payload[base + 5]),
            switchState: Int(payload[base + 6])
        )
    }
}
