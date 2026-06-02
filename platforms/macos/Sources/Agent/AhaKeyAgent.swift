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
    private let deviceNamePrefix = "vibe code"
    private let socketPath: String

    private let header: [UInt8] = [0xAA, 0xBB]
    private let trailer: [UInt8] = [0xCC, 0xDD]

    // MARK: 缓存（供 hook 查询使用）
    /// 最新 switchState（0=auto, 1=manual），未知时 nil
    private(set) var cachedSwitchState: UInt8?
    /// 最新 lightMode
    private(set) var cachedLightMode: UInt8?

    /// 等待下一次 status 回包的回调队列（用于 querySwitchState）
    private var statusWaiters: [(AgentDeviceStatus?) -> Void] = []

    var onLog: ((String) -> Void)?

    init(socketPath: String = "/tmp/ahakey.sock") {
        self.socketPath = socketPath
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public

    func sendState(_ state: UInt8) {
        guard let commandChar, let peripheral else {
            emit("LED 状态 \(state): 未连接")
            return
        }
        let data = Data(header + [0x90, state] + trailer)
        let wt: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: wt)
        emit("→ LED 状态 \(state): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
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

    func startSocketListener() {
        // 清理旧 socket
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { emit("socket() 失败"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let buf = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                strcpy(buf, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { emit("bind() 失败: \(errno)"); close(fd); return }

        listen(fd, 5)
        emit("监听 Unix socket: \(socketPath)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let clientFd = accept(fd, nil, nil)
                guard clientFd >= 0 else { continue }
                self?.handleClient(clientFd)
            }
        }
    }

    // MARK: - Socket handling

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
                sendState(UInt8(clamping: v))
            }
            Self.replyAndClose(clientFd, ["ok": true])

        case "permission":
            // 发 PermissionRequest 对应的 state（默认 1），同时主动查询拨杆
            let stateValue = obj["value"] as? Int ?? 1
            sendState(UInt8(clamping: stateValue))
            querySwitchState(timeout: 1.5) { status in
                let body = Self.statusReply(status, cachedSwitch: self.cachedSwitchState, cachedLight: self.cachedLightMode)
                self.emit("← permission 回包 switchState=\(String(describing: body["switchState"]))")
                if let s = body["switchState"] as? Int, s != 0 {
                    self.emit("（拨杆非 0：PermissionRequest 将交回终端手动确认）")
                } else if body["switchState"] is NSNull {
                    self.emit("（switchState 缺省：批准链可能仍交回手动；请把「蓝牙」交给 Agent 并连上键盘。）")
                }
                Self.replyAndClose(clientFd, body)
            }

        case "status":
            if cachedSwitchState != nil {
                Self.replyAndClose(clientFd, [
                    "switchState": cachedSwitchState.map { Int($0) } ?? NSNull(),
                    "lightMode": cachedLightMode.map { Int($0) } ?? NSNull(),
                ])
            } else {
                querySwitchState(timeout: 1.5) { status in
                    Self.replyAndClose(clientFd, Self.statusReply(status, cachedSwitch: self.cachedSwitchState, cachedLight: self.cachedLightMode))
                }
            }

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
        if let p = connected.first(where: { ($0.name ?? "").lowercased().hasPrefix(deviceNamePrefix) }) {
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
        guard name.lowercased().hasPrefix(deviceNamePrefix) else { return }
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
