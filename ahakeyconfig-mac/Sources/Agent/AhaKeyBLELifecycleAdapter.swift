import Foundation
import AhaKeyConfigShared

/// BLE 连接生命周期的串行边界：Core 状态、probe timer、retrieve/connect 必须在此队列执行。
/// 生产 `CBCentralManager(queue: nil)` 也投递到 main；测试不得绕过该断言。
enum AhaKeyBLELifecycleSeam {
    static func assertIsolated() {
        dispatchPrecondition(condition: .onQueue(.main))
    }

    static func run(_ body: () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.sync(execute: body)
        }
    }
}

/// 扫描期 `retrieveConnectedPeripherals` 判定。空结果不得产生常规日志。
enum AhaKeySystemAttachedProbe {
    struct PeripheralRef: Equatable {
        var name: String?
        var uuid: String
    }

    enum Decision: Equatable {
        case miss
        case hit(name: String, uuid: String)
    }

    static func decide(attached: [PeripheralRef], namePrefix: String) -> Decision {
        let prefix = namePrefix.lowercased()
        guard let match = attached.first(where: {
            ($0.name ?? "").lowercased().hasPrefix(prefix)
        }) else {
            return .miss
        }
        return .hit(name: match.name ?? "?", uuid: match.uuid)
    }

    static func logMessage(for decision: Decision) -> String? {
        switch decision {
        case .miss:
            return nil
        case .hit(let name, _):
            return "系统已连接: \(name)"
        }
    }
}

protocol AhaKeyBLEProbeScheduling: AnyObject {
    func scheduleProbe(after: TimeInterval, token: UInt64, fire: @escaping () -> Void)
    func cancelProbe()
}

final class AhaKeyBLEMainQueueProbeScheduler: AhaKeyBLEProbeScheduling {
    private var item: DispatchWorkItem?

    func scheduleProbe(after: TimeInterval, token: UInt64, fire: @escaping () -> Void) {
        item?.cancel()
        let work = DispatchWorkItem(block: fire)
        item = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }

    func cancelProbe() {
        item?.cancel()
        item = nil
    }
}

/// 生产 Adapter：Core 决策 + 单次 retrieve 快照直连。Host 只落地 CoreBluetooth/日志。
final class AhaKeyBLELifecycleAdapter {
    protocol Host: AnyObject {
        func retrieveSystemAttached() -> [AhaKeySystemAttachedProbe.PeripheralRef]
        /// 使用**同一次** retrieve 得到的外设启动连接；不得再查系统已连列表。
        func connectRetrieved(uuid: String) -> Bool
        func connectKnown(uuid: String)
        func startScan()
        func stopScan()
        func acquireConnectionLock() -> Bool
        func discoverServices(uuid: String)
        func sendCapabilityNegotiation(uuid: String)
        func disconnect(uuid: String)
        func emit(_ message: String)
        func scheduleReconnect(after: TimeInterval)
    }

    var core = DeviceTransportCore(sessionGeneration: 1)
    weak var host: Host?
    private let namePrefix: String
    private let scheduler: AhaKeyBLEProbeScheduling
    /// 最近一次 retrieve 快照；connect 只读这里，禁止二次查询。
    private var retrievedSnapshot: [AhaKeySystemAttachedProbe.PeripheralRef] = []

    init(
        namePrefix: String = "AhaKey",
        scheduler: AhaKeyBLEProbeScheduling = AhaKeyBLEMainQueueProbeScheduler()
    ) {
        self.namePrefix = namePrefix
        self.scheduler = scheduler
    }

    func handle(_ event: DeviceTransportEvent, now: Date) {
        AhaKeyBLELifecycleSeam.assertIsolated()
        perform(core.handle(event, now: now), now: now)
    }

    func shutdown(now: Date) {
        AhaKeyBLELifecycleSeam.assertIsolated()
        perform(core.handle(.shutdown, now: now), now: now)
    }

    func perform(_ actions: [DeviceTransportAction], now: Date) {
        AhaKeyBLELifecycleSeam.assertIsolated()
        guard let host else { return }
        for action in actions {
            switch action {
            case .acquireConnectionLock:
                if host.acquireConnectionLock() {
                    handle(.lockAcquired, now: now)
                } else {
                    _ = core.handle(.lockBusy, now: now)
                }
            case .scan:
                retrieveOnceAndAttach(host: host, startScanOnMiss: true, now: now)
            case .resumeScanning:
                host.startScan()
            case .connectKnown(let uuid):
                host.connectKnown(uuid: uuid)
            case .connectSystemAttached(let uuid):
                connectFromSnapshot(uuid: uuid, host: host, now: now)
            case .discoverServices(let uuid):
                host.discoverServices(uuid: uuid)
            case .sendCapabilityNegotiation(let uuid):
                host.sendCapabilityNegotiation(uuid: uuid)
            case .disconnect(let uuid):
                host.disconnect(uuid: uuid)
            case .scheduleReconnectTimer(let after):
                host.scheduleReconnect(after: after)
            case .scheduleSystemAttachedProbe(let after, let token):
                guard token == core.systemAttachedProbeToken,
                      case .scanning = core.phase else { break }
                scheduler.scheduleProbe(after: after, token: token) { [weak self] in
                    AhaKeyBLELifecycleSeam.run {
                        self?.handle(.systemAttachedProbeFired(token: token), now: Date())
                    }
                }
            case .cancelSystemAttachedProbe:
                scheduler.cancelProbe()
            case .probeSystemAttached:
                retrieveOnceAndAttach(host: host, startScanOnMiss: false, now: now)
            }
        }
    }

    private func retrieveOnceAndAttach(host: Host, startScanOnMiss: Bool, now: Date) {
        retrievedSnapshot = host.retrieveSystemAttached()
        let decision = AhaKeySystemAttachedProbe.decide(
            attached: retrievedSnapshot,
            namePrefix: namePrefix
        )
        switch decision {
        case .miss:
            if startScanOnMiss {
                host.emit(NSLocalizedString("开始扫描…", comment: ""))
                host.startScan()
            } else {
                handle(.systemAttachedProbeEmpty, now: now)
            }
        case .hit(_, let uuid):
            handle(.systemAttachedDeviceFound(uuid: uuid), now: now)
        }
    }

    private func connectFromSnapshot(uuid: String, host: Host, now: Date) {
        guard retrievedSnapshot.contains(where: { $0.uuid == uuid }) else {
            handle(.lookupOrConnectFailed, now: now)
            return
        }
        let decision = AhaKeySystemAttachedProbe.decide(
            attached: retrievedSnapshot,
            namePrefix: namePrefix
        )
        host.stopScan()
        guard host.connectRetrieved(uuid: uuid) else {
            handle(.lookupOrConnectFailed, now: now)
            return
        }
        if let message = AhaKeySystemAttachedProbe.logMessage(for: decision) {
            host.emit(message)
        }
    }
}
