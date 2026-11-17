import Foundation
import XCTest
@testable import AhaKeyConfig

final class HIDFunctionKeyBridgeTests: XCTestCase {
    func testOwnedMappingRestoresOnModeExitAndPreservesExternalEntries() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let other = [HIDFunctionKeyBridge.sourceKey: UInt64(0x700000039),
                     HIDFunctionKeyBridge.destinationKey: UInt64(0x700000029)]
        let added = [HIDFunctionKeyBridge.sourceKey: UInt64(0x70000004C),
                     HIDFunctionKeyBridge.destinationKey: UInt64(0x70000004D)]
        var table = [other]
        let selected = HIDFunctionKeyBridge.Device(id: 42, read: { table }, write: { table = $0; return true })
        let bridge = HIDFunctionKeyBridge(devices: { [selected] }, defaults: defaults)

        XCTAssertTrue(bridge.reconcile(enabled: true))
        XCTAssertEqual(table, [other, HIDFunctionKeyBridge.entry])
        table.append(added)
        let restarted = HIDFunctionKeyBridge(devices: { [selected] }, defaults: defaults)
        XCTAssertFalse(restarted.reconcile(enabled: false))
        XCTAssertEqual(table, [other, added])
    }

    func testAmbiguousDevicesAndPreexistingF19MappingsAreNeverChanged() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let existing = HIDFunctionKeyBridge.entry
        var table = [existing]
        let one = HIDFunctionKeyBridge.Device(id: 42, read: { table }, write: { _ in XCTFail("foreign mapping"); return false })
        let two = HIDFunctionKeyBridge.Device(id: 43, read: { [] }, write: { _ in XCTFail("ambiguous device"); return false })
        var attached = [one, two]
        let bridge = HIDFunctionKeyBridge(devices: { attached }, defaults: defaults)
        XCTAssertFalse(bridge.reconcile(enabled: true))
        attached = [one]
        XCTAssertFalse(bridge.reconcile(enabled: true))
        XCTAssertFalse(bridge.reconcile(enabled: false))
        XCTAssertEqual(table, [existing])
        table = [[HIDFunctionKeyBridge.sourceKey: HIDFunctionKeyBridge.f19,
                  HIDFunctionKeyBridge.destinationKey: 0x700000029]]
        XCTAssertFalse(bridge.reconcile(enabled: true))
    }
}
