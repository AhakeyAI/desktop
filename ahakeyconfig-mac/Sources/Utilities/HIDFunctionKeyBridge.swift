import Foundation
import IOKit.hidsystem

/// A per-keyboard lease. A Quartz event can look like Fn to an event tap
/// without changing the keyboard service's modifier state.
final class HIDFunctionKeyBridge {
    typealias Map = [[String: UInt64]]
    struct Device {
        let id: UInt64
        let read: () -> Map?
        let write: (Map) -> Bool
    }

    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"
    static let f19: UInt64 = 0x000000070000006E
    static let fn: UInt64 = 0x000000FF00000003 // Apple Vendor Top Case, Keyboard Fn.
    static let entry = [sourceKey: f19, destinationKey: fn]

    private let devices: () -> [Device]
    private let defaults: UserDefaults
    private let bootSession: String?
    private let journalKey = "ahaKeyOwnedHIDFnMapping"
    private var owned: UInt64?

    init(devices: @escaping () -> [Device] = HIDFunctionKeyBridge.keyboards,
         defaults: UserDefaults = .standard) {
        self.devices = devices
        self.defaults = defaults
        bootSession = Self.currentBootSession()
        if let bootSession, let journal = defaults.dictionary(forKey: journalKey),
           journal["boot"] as? String == bootSession {
            owned = (journal["id"] as? NSNumber)?.uint64Value
        }
    }

    /// Call on one serial queue. Ambiguous targets and user-owned mappings
    /// are left alone. The fallback can still serve older keyboard routes.
    @discardableResult
    func reconcile(enabled: Bool) -> Bool {
        let connected = devices()
        let target = enabled && connected.count == 1 ? connected.first : nil
        if let owned, owned != target?.id {
            if let device = connected.first(where: { $0.id == owned }) {
                guard let map = device.read() else { return false }
                if map.contains(Self.entry) {
                    guard device.write(map.filter { $0 != Self.entry }),
                          device.read()?.contains(Self.entry) == false else { return false }
                }
            }
            setOwned(nil)
        }
        guard let target, let map = target.read() else { return false }
        if owned == target.id, map.contains(Self.entry) { return true }
        if owned == target.id { setOwned(nil) }
        guard !map.contains(where: { $0[Self.sourceKey] == Self.f19 }) else { return false }
        // Record intent before the write, so a subsequent launch can undo it.
        setOwned(target.id)
        guard target.write(map + [Self.entry]), target.read()?.contains(Self.entry) == true else {
            // Keep the journal if readback is unavailable; reconcile before claiming another device.
            if target.read()?.contains(Self.entry) == false { setOwned(nil) }
            return false
        }
        return true
    }

    private func setOwned(_ id: UInt64?) {
        owned = id
        if let id, let bootSession { defaults.set(["id": NSNumber(value: id), "boot": bootSession], forKey: journalKey) }
        else { defaults.removeObject(forKey: journalKey) }
    }

    private static func currentBootSession() -> String? {
        var bytes = [CChar](repeating: 0, count: 64)
        var length = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &length, nil, 0) == 0,
              length > 1, length <= bytes.count else { return nil }
        return bytes.withUnsafeBufferPointer { $0.baseAddress.map(String.init(cString:)) }
    }

    private static func keyboards() -> [Device] {
        let system = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = IOHIDEventSystemClientCopyServices(system) as? [IOHIDServiceClient] ?? []
        return services.compactMap { service in
            func property(_ name: String) -> CFTypeRef? { IOHIDServiceClientCopyProperty(service, name as CFString) }
            func number(_ name: String) -> Int? { (property(name) as? NSNumber)?.intValue }
            guard number("VendorID") == 0x07D7, number("ProductID") == 0,
                  number("PrimaryUsagePage") == 1, number("PrimaryUsage") == 6,
                  (property("Transport") as? String) == "Bluetooth Low Energy",
                  (property("Product") as? String)?.hasPrefix("AhaKey ") == true,
                  let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { return nil }
            return Device(id: id, read: {
                // Keep the client alive for the lifetime of its service.
                withExtendedLifetime(system) {
                    guard let value = property("UserKeyMapping"), !(value is NSNull) else { return [] }
                    return value as? Map
                }
            }, write: { mappings in
                withExtendedLifetime(system) {
                    IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, mappings as CFArray)
                }
            })
        }
    }
}
