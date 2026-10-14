import XCTest
@testable import AhaKeyConfigShared

final class ConfirmedSideSwitchSettingTests: XCTestCase {
    private let factory: [SideSwitchReadback.Position] = [.init(bindType: 0, action: Data()), .init(bindType: 1, action: Data())]
    private let disabled = SideSwitchReadback.Position(bindType: 2, action: Data())
    private var custom: SideSwitchReadback.Position { .init(bindType: 3, action: Data([0x73, 2, 0xE3, 0x28])) }
    private func readback(_ positions: [SideSwitchReadback.Position], physical: UInt8 = 1) -> SideSwitchReadback {
        .init(physicalState: physical, positions: positions)
    }
    func testTwoPositionWireAndNarrowGrant() {
        let wire = SideSwitchBindingConfiguration.request(positions: [custom, disabled])!
        XCTAssertEqual(wire, Data([0xAA, 0xBB, 0x97, 1, 3, 4, 0x73, 2, 0xE3, 0x28, 2, 0, 0xCC, 0xDD]))
        let known = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: known))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(wire, profile: known, confirmedWrite: .sideSwitch))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: nil, confirmedWrite: .sideSwitch))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: known, confirmedWrite: .standby))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: known, confirmedWrite: .sideSwitch))
        XCTAssertFalse(SideSwitchBindingConfiguration.validRequest(wire + Data([0])))
        var wrong = wire; wrong[3] = 2
        XCTAssertFalse(SideSwitchBindingConfiguration.validRequest(wrong))
        wrong = wire; wrong[5] = 5
        XCTAssertFalse(SideSwitchBindingConfiguration.validRequest(wrong))
    }
    func testCustomPeerDefaultsAndExplicitFactoryChoice() {
        var draft = SideSwitchBindingDraft(readback: readback(factory))
        draft.set(custom, at: 0)
        XCTAssertEqual(draft.positions, [custom, disabled])
        draft.set(factory[1], at: 1)
        draft.set(custom, at: 0)
        XCTAssertEqual(draft.positions, [custom, factory[1]])
        var opposite = SideSwitchBindingDraft(readback: readback(factory))
        opposite.set(custom, at: 1)
        XCTAssertEqual(opposite.positions, [disabled, custom])
    }
    func testActionBoundsAndHeldModifierProtection() {
        XCTAssertFalse(SideSwitchBindingConfiguration.validAction(Data([0x73, 0])))
        XCTAssertFalse(SideSwitchBindingConfiguration.validAction(Data([0x73, 2, 0xE3])))
        XCTAssertFalse(SideSwitchBindingConfiguration.validAction(Data([0x73, 2, 0x28, 0x28])))
        XCTAssertFalse(SideSwitchBindingConfiguration.validAction(Data([0x74, 2, 1, 0xE3])))
        XCTAssertTrue(SideSwitchBindingConfiguration.validAction(Data([0x74, 4, 1, 0xE3, 4, 0])))
        XCTAssertTrue(SideSwitchBindingConfiguration.validAction(Data([0x74, 4, 1, 0xE3, 2, 0xE3])))
        XCTAssertFalse(SideSwitchBindingConfiguration.validAction(Data([0x74, 2, 2, 0xE3])))
        XCTAssertFalse(SideSwitchBindingConfiguration.validAction(Data([0x74, 2, 5, 0])))
        XCTAssertFalse(SideSwitchBindingConfiguration.request(positions: [.init(bindType: 0, action: custom.action), disabled]) != nil)
        let maximum = Data([0x74, 50] + Array(repeating: [UInt8(3), UInt8(0xCC)], count: 25).flatMap { $0 })
        XCTAssertTrue(SideSwitchBindingConfiguration.validAction(maximum))
        XCTAssertNotNil(SideSwitchBindingConfiguration.request(positions: [.init(bindType: 3, action: maximum), disabled]))
        XCTAssertNil(SideSwitchBindingConfiguration.request(positions: [.init(bindType: 3, action: maximum), custom]))
    }
    @MainActor
    func testReadWriteAckReadIgnoresPhysicalMovementAndNoOp() async throws {
        let target = [custom, disabled]
        var reads = [readback(factory), readback(target, physical: 0)], events: [String] = []
        let actual = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: target, checkSession: {}, read: {
            events.append("read"); return reads.removeFirst()
        }, write: { frame in events.append("97"); XCTAssertTrue(SideSwitchBindingConfiguration.validRequest(frame)) })
        XCTAssertEqual(actual.positions, target)
        XCTAssertEqual(events, ["read", "97", "read"])
        _ = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: factory, checkSession: {}, read: { self.readback(self.factory) }, write: { _ in XCTFail("no-op") })
    }
    @MainActor
    func testConcurrentExternalChangeDoesNotOverwritePeer() async {
        do {
            _ = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: [custom, disabled], checkSession: {}, read: { self.readback([self.disabled, self.disabled]) }, write: { _ in XCTFail("conflict must stop") })
            XCTFail("changed since read")
        } catch { XCTAssertEqual(error as? ConfirmedSideSwitchSetting.Failure, .changedSinceRead) }
    }
    @MainActor
    func testAckAloneAndRejectionAreNotSuccess() async {
        do {
            _ = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: [custom, disabled], checkSession: {}, read: { self.readback(self.factory) }, write: { _ in })
            XCTFail("ACK alone")
        } catch { XCTAssertEqual(error as? ConfirmedSideSwitchSetting.Failure, .mismatch) }
        var reads = 0
        do {
            _ = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: [custom, disabled], checkSession: {}, read: { reads += 1; return self.readback(self.factory) }, write: { _ in throw CancellationError() })
            XCTFail("failed write")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }
    @MainActor
    func testDisconnectAfterAckAndReadbackFailureRemainUnconfirmed() async {
        var valid = true, reads = 0
        do {
            _ = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: [custom, disabled], checkSession: { if !valid { throw CancellationError() } }, read: { reads += 1; return self.readback(self.factory) }, write: { _ in valid = false })
            XCTFail("new session cannot finish old write")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
        reads = 0
        do {
            _ = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: [custom, disabled], checkSession: {}, read: {
                reads += 1; if reads == 2 { throw CancellationError() }; return self.readback(self.factory)
            }, write: { _ in })
            XCTFail("readback failed")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
