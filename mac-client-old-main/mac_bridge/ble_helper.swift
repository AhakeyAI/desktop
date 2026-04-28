import Foundation
import CoreBluetooth

// MARK: - JSON通信协议
// stdin接收命令: {"cmd":"scan","name":"xxx"} / {"cmd":"connect","address":"xxx"} / {"cmd":"write_data","data":"base64"} / {"cmd":"write_command","data":"base64"} / {"cmd":"disconnect"} / {"cmd":"stop"}
// stdout发送事件: {"event":"ready"} / {"event":"discovered","name":"xxx","address":"xxx","rssi":-50} / {"event":"connected","name":"xxx","address":"xxx"} / {"event":"characteristics_ready"} / {"event":"notify","data":"base64"} / {"event":"disconnected"} / {"event":"log","message":"xxx"} / {"event":"error","message":"xxx"}

let UUID_SERVICE = CBUUID(string: "7340")
let UUID_DATA    = CBUUID(string: "7341")
let UUID_COMMAND = CBUUID(string: "7343")
let UUID_NOTIFY  = CBUUID(string: "7344")

class BleHelper: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var peripheral: CBPeripheral?
    var charData: CBCharacteristic?
    var charCommand: CBCharacteristic?
    var charNotify: CBCharacteristic?
    
    var targetName: String?
    var targetAddress: String?
    var scanning = false
    var pendingScan = false
    var characteristicsReady = false
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - 输出JSON事件
    func emit(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            print(str)
            fflush(stdout)
        }
    }
    
    func emitEvent(_ event: String, _ extra: [String: Any] = [:]) {
        var d = extra
        d["event"] = event
        emit(d)
    }
    
    func log(_ msg: String) { emitEvent("log", ["message": msg]) }

    private func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func genericVibePrefix() -> String {
        "vibe code"
    }

    private func isGenericVibeCodeName(_ name: String) -> Bool {
        let current = normalizedName(name)
        return !current.isEmpty && current.hasPrefix(genericVibePrefix())
    }

    private func shouldAllowGenericVibeFallback(target: String?) -> Bool {
        guard let target else { return true }
        let expected = normalizedName(target)
        if expected.isEmpty {
            return true
        }
        return expected.hasPrefix(genericVibePrefix())
    }

    private func matchesTargetName(_ name: String, target: String) -> Bool {
        let current = normalizedName(name)
        let expected = normalizedName(target)
        guard !current.isEmpty, !expected.isEmpty else { return false }
        if current == expected || current.hasPrefix(expected) {
            return true
        }
        // 如果之前保存的是某个具体的 vibe code 设备名（例如 "vibe code 1565"），
        // 但用户后来换了新的设备，也允许回退匹配新的 "vibe code*" 设备。
        if shouldAllowGenericVibeFallback(target: target) && current.hasPrefix(genericVibePrefix()) {
            return true
        }
        return false
    }

    private func peripheralDisplayName(_ peripheral: CBPeripheral) -> String {
        let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? peripheral.identifier.uuidString : name
    }

    private func attachPeripheral(_ candidate: CBPeripheral, reason: String) {
        peripheral = candidate
        candidate.delegate = self
        let name = peripheralDisplayName(candidate)
        let address = candidate.identifier.uuidString

        if candidate.state == .connected {
            log("\(reason): \(name) [\(address)]，设备已由系统保持连接，直接发现服务...")
            emitEvent("connected", ["name": name, "address": address])
            candidate.discoverServices(nil)
            return
        }

        log("\(reason): \(name) [\(address)]，开始连接...")
        central.connect(candidate, options: nil)
    }

    private func selectConnectedPeripheral(_ peripherals: [CBPeripheral]) -> CBPeripheral? {
        if let ta = targetAddress, !ta.isEmpty {
            if let match = peripherals.first(where: { $0.identifier.uuidString.lowercased() == ta.lowercased() }) {
                return match
            }
        }

        if let tn = targetName, !tn.isEmpty {
            if let match = peripherals.first(where: { matchesTargetName(peripheralDisplayName($0), target: tn) }) {
                return match
            }
        }

        if let genericMatch = peripherals.first(where: { isGenericVibeCodeName(peripheralDisplayName($0)) }) {
            return genericMatch
        }

        if peripherals.count == 1 {
            return peripherals[0]
        }

        return nil
    }
    
    // MARK: - 命令处理
    func handleCommand(_ json: [String: Any]) {
        guard let cmd = json["cmd"] as? String else { return }
        switch cmd {
        case "scan":
            targetName = json["name"] as? String
            targetAddress = json["address"] as? String
            startScan()
        case "connect":
            targetAddress = json["address"] as? String
            targetName = json["name"] as? String
            startScan()
        case "write_data":
            if let b64 = json["data"] as? String, let data = Data(base64Encoded: b64) {
                writeData(data)
            }
        case "write_command":
            if let b64 = json["data"] as? String, let data = Data(base64Encoded: b64) {
                writeCommand(data)
            }
        case "disconnect":
            disconnect()
        case "stop":
            disconnect()
            exit(0)
        default:
            log("未知命令: \(cmd)")
        }
    }
    
    func startScan() {
        guard central.state == .poweredOn else {
            pendingScan = true
            log("蓝牙未就绪, 等待...")
            return
        }

        // 优先尝试直接重连已知设备（不需要重新扫描）
        if let p = peripheral {
            attachPeripheral(p, reason: "连接策略: 使用内存中的已知设备直接重连")
            return
        }

        // 尝试通过 UUID 检索系统缓存的设备
        if let ta = targetAddress, !ta.isEmpty, let uuid = UUID(uuidString: ta) {
            log("连接策略: 优先用已保存 UUID 直连 \(ta)")
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let p = known.first {
                attachPeripheral(p, reason: "已命中系统缓存设备")
                return
            }
            log("已保存 UUID 未命中系统缓存，回退到扫描模式...")
        }

        let connectedPeripherals = central.retrieveConnectedPeripherals(withServices: [UUID_SERVICE])
        if !connectedPeripherals.isEmpty {
            log("系统已连接 \(connectedPeripherals.count) 个包含 7340 服务的 BLE 设备")
            if let selected = selectConnectedPeripheral(connectedPeripherals) {
                attachPeripheral(selected, reason: "连接策略: 从系统已连接 BLE 设备中命中目标")
                return
            }

            let summary = connectedPeripherals
                .map { "\(peripheralDisplayName($0)) [\($0.identifier.uuidString)]" }
                .joined(separator: ", ")
            log("系统已连接设备未命中名称/UUID 规则，候选设备: \(summary)")
        } else {
            log("系统当前没有已连接且暴露 7340 服务的 BLE 设备")
        }

        scanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if let ta = targetAddress, !ta.isEmpty {
            if let tn = targetName, !tn.isEmpty {
                log("开始扫描，优先匹配 UUID: \(ta)，同时接受名称前缀: \(tn)，若旧设备不存在则回退到任意 vibe code* 设备")
            } else {
                log("开始扫描，目标设备 UUID: \(ta)")
            }
        } else if let tn = targetName, !tn.isEmpty {
            log("开始扫描，目标名称前缀: \(tn)，若旧设备不存在则回退到任意 vibe code* 设备")
        } else {
            log("开始扫描，接受名称以 vibe code 开头的设备...")
        }
    }

    func stopScan() {
        if scanning { central.stopScan(); scanning = false }
    }

    func disconnect() {
        stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil  // 主动断开时清除引用
        resetChars()
    }

    func resetChars() {
        charData = nil; charCommand = nil; charNotify = nil
        characteristicsReady = false
    }
    
    func bestWriteType(for c: CBCharacteristic) -> CBCharacteristicWriteType {
        // 优先用 withoutResponse（快），但如果特征不支持则用 withResponse
        if c.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }
        return .withResponse
    }

    func writeData(_ data: Data) {
        guard let c = charData, let p = peripheral else {
            log("writeData 失败: 特征或设备未就绪")
            return
        }
        let wt = bestWriteType(for: c)
        p.writeValue(data, for: c, type: wt)
        log("writeData [\(data.count)字节] type=\(wt == .withoutResponse ? "noResp" : "withResp")")
    }

    func writeCommand(_ data: Data) {
        guard let c = charCommand, let p = peripheral else {
            log("writeCommand 失败: 特征或设备未就绪")
            return
        }
        let wt = bestWriteType(for: c)
        p.writeValue(data, for: c, type: wt)
        log("writeCommand [\(data.count)字节] type=\(wt == .withoutResponse ? "noResp" : "withResp") data=\(data.map { String(format: "%02X", $0) }.joined())")
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("蓝牙状态: \(central.state.rawValue)")
        if central.state == .poweredOn {
            emitEvent("ready")
            if pendingScan { pendingScan = false; startScan() }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (p.name?.isEmpty == false ? p.name! : (advName ?? ""))
        guard !name.isEmpty else { return }
        let addr = p.identifier.uuidString
        emitEvent("discovered", ["name": name, "address": addr, "rssi": RSSI.intValue])
        
        let matchedByAddress: Bool
        if let ta = targetAddress, !ta.isEmpty {
            matchedByAddress = addr.lowercased() == ta.lowercased()
        } else {
            matchedByAddress = false
        }

        let matchedByName: Bool
        if let tn = targetName, !tn.isEmpty {
            matchedByName = matchesTargetName(name, target: tn)
        } else {
            matchedByName = isGenericVibeCodeName(name)
        }

        if matchedByAddress || matchedByName {
            if matchedByAddress {
                log("匹配目标 UUID: \(name), 连接中...")
            } else {
                log("匹配目标名称规则: \(name), 连接中...")
            }
            stopScan()
            attachPeripheral(p, reason: "扫描命中目标")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        emitEvent("connected", ["name": p.name ?? "", "address": p.identifier.uuidString])
        p.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        resetChars()
        // 注意：不清除 peripheral 引用，保留它以便直接重连
        emitEvent("disconnected")
        log("设备已断开: \(p.name ?? "")")
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        emitEvent("error", ["message": "连接失败: \(error?.localizedDescription ?? "未知")"])
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error { log("服务发现错误: \(err.localizedDescription)"); return }
        guard let services = peripheral.services else { return }
        log("发现 \(services.count) 个服务")
        for s in services {
            log("  服务: \(s.uuid)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error { log("特征发现错误: \(err.localizedDescription)"); return }
        guard let chars = service.characteristics else { return }
        for c in chars {
            let props = c.properties
            var propList: [String] = []
            if props.contains(.read) { propList.append("read") }
            if props.contains(.write) { propList.append("write") }
            if props.contains(.writeWithoutResponse) { propList.append("writeNoResp") }
            if props.contains(.notify) { propList.append("notify") }
            if props.contains(.indicate) { propList.append("indicate") }
            log("  特征: \(c.uuid) [\(propList.joined(separator: ","))]")
            if c.uuid == UUID_DATA {
                charData = c
                log("  → 数据特征(0x7341)已就绪")
            } else if c.uuid == UUID_COMMAND {
                charCommand = c
                log("  → 命令特征(0x7343)已就绪")
            } else if c.uuid == UUID_NOTIFY {
                charNotify = c
                peripheral.setNotifyValue(true, for: c)
                log("  → 通知特征(0x7344)已就绪, 已订阅")
            }
        }
        if !characteristicsReady && charData != nil && charCommand != nil && charNotify != nil {
            characteristicsReady = true
            log("所有目标特征已就绪!")
            emitEvent("characteristics_ready")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            log("写入失败 [\(characteristic.uuid)]: \(err.localizedDescription)")
        } else {
            log("写入成功 [\(characteristic.uuid)]")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error { log("通知错误: \(err.localizedDescription)"); return }
        guard let data = characteristic.value else { return }
        emitEvent("notify", ["data": data.base64EncodedString()])
    }
}

// MARK: - stdin读取线程
func stdinReader(_ helper: BleHelper) {
    DispatchQueue.global(qos: .userInitiated).async {
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            DispatchQueue.main.async { helper.handleCommand(json) }
        }
        // stdin关闭 = 父进程退出
        exit(0)
    }
}

// MARK: - 入口
let helper = BleHelper()
stdinReader(helper)
RunLoop.main.run()
