import Foundation
import AhaKeyConfigShared

/// Local history protects drafts across process restarts. It is never a current
/// connection fact, a persistence receipt, or permission to write a device.
struct StudioDeviceDraftHistory: Codable {
    struct Record: Codable {
        var standby: UInt16?
        var standbyBaseline: UInt16?
        var lever: SideSwitchBindingDraft?
        var leverBaseline: [SideSwitchReadback.Position]?
        var unconfirmedStandby = false
        var unconfirmedLever = false
    }
    static let storageKey = "ahakey.studio.device-drafts.v1"
    private(set) var records: [String: Record] = [:]
    private(set) var order: [String] = []
    var lastDeviceID: String? { order.last }
    subscript(_ deviceID: String?) -> Record? { deviceID.flatMap { records[$0] } }

    mutating func save(_ record: Record, deviceID: String) {
        guard Self.validID(deviceID), Self.valid(record) else { return }
        records[deviceID] = record
        order.removeAll { $0 == deviceID }; order.append(deviceID)
        while order.count > 32 { records.removeValue(forKey: order.removeFirst()) }
    }
    static func load(from defaults: UserDefaults) -> Self {
        guard let bytes = defaults.data(forKey: storageKey), bytes.count <= 256_000,
              let history = try? JSONDecoder().decode(Self.self, from: bytes),
              history.records.count <= 32, history.order.count == history.records.count,
              Set(history.order).count == history.order.count,
              Set(history.order) == Set(history.records.keys),
              history.records.allSatisfy({ validID($0.key) && valid($0.value) }) else { return .init() }
        return history
    }
    func persist(to defaults: UserDefaults) {
        if let bytes = try? JSONEncoder().encode(self) { defaults.set(bytes, forKey: Self.storageKey) }
    }
    private static func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 128 }
    private static func valid(_ record: Record) -> Bool {
        let minutes = [record.standby, record.standbyBaseline].compactMap { $0 }
        guard minutes.allSatisfy({ ConfirmedStandbySetting.supportedMinutes.contains($0) }) else { return false }
        for positions in [record.lever?.positions, record.leverBaseline].compactMap({ $0 }) {
            // Retain incomplete editing drafts too; write validation remains separate.
            guard positions.count == 2, positions.allSatisfy({ $0.bindType <= 3 && $0.action.count <= 100 }) else { return false }
        }
        return true
    }
}
