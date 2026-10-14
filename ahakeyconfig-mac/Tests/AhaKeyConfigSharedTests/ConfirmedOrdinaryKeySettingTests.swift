import XCTest
@testable import AhaKeyConfigShared

final class ConfirmedOrdinaryKeySettingTests: XCTestCase {
    private func key(_ action: [UInt8] = [0x2A], description: String = "Backspace", index: UInt8 = 3) -> OrdinaryKeyReadback {
        .init(mode: 2, keyIndex: index, actionType: 0x73, action: Data(action), description: Data(description.utf8))
    }
    func testEncodingCapacityAndScopedGrant() {
        let k = key([0xE3, 0x28])
        let wire = OrdinaryKeyConfiguration.actionRequest(k)!
        XCTAssertEqual(wire, Data([0xAA, 0xBB, 0x73, 0x73, 2, 3, 0xE3, 0x28, 0xCC, 0xDD]))
        XCTAssertEqual(OrdinaryKeyConfiguration.descriptionRequest(key(description: "X")), Data([0xAA, 0xBB, 0x73, 0x75, 2, 3, 0x58, 0xCC, 0xDD]))
        let known = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: known))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(wire, profile: known, confirmedWrite: .ordinaryKey))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: known, confirmedWrite: .sideSwitch))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(wire, profile: nil, confirmedWrite: .ordinaryKey))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x80, 0, 0xCC, 0xDD]), profile: known, confirmedWrite: .ordinaryKey))
        XCTAssertNil(OrdinaryKeyConfiguration.descriptionRequest(key(description: "中文")))
        XCTAssertNil(OrdinaryKeyConfiguration.descriptionRequest(key(description: "X ")))
        XCTAssertFalse(OrdinaryKeyConfiguration.valid(key(description: String(repeating: "X", count: 21))))
        let macro = Data(Array(repeating: [UInt8(3), 1], count: 25).flatMap { $0 })
        XCTAssertTrue(OrdinaryKeyConfiguration.valid(.init(mode: 2, keyIndex: 3, actionType: 0x74, action: macro, description: Data("XYZ".utf8))))
        XCTAssertFalse(OrdinaryKeyConfiguration.valid(.init(mode: 2, keyIndex: 3, actionType: 0x74, action: macro, description: Data("XYZW".utf8))))
        let boundary = Data(Array(repeating: [UInt8(3), 1], count: 26).flatMap { $0 })
        XCTAssertTrue(OrdinaryKeyConfiguration.valid(.init(mode: 2, keyIndex: 3, actionType: 0x74, action: boundary, description: Data([0x58]))))
        XCTAssertFalse(OrdinaryKeyConfiguration.valid(.init(mode: 2, keyIndex: 3, actionType: 0x74, action: boundary, description: Data([0x58, 0x59]))))
        XCTAssertTrue(OrdinaryKeyConfiguration.valid(key([])))
        var malformed = wire; malformed[4] = 4
        XCTAssertFalse(OrdinaryKeyConfiguration.validWriteRequest(malformed))
    }
    @MainActor
    func testOnlyChangedFieldsThenSaveAndRead() async throws {
        let baseline = key(), target = key(description: "Test")
        var reads = [baseline, target], writes: [Data] = []
        let actual = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {}, read: { reads.removeFirst() }, voiceState: { XCTFail("not Voice"); return 2 }, write: { writes.append($0) })
        XCTAssertEqual(actual, target)
        XCTAssertEqual(writes, [OrdinaryKeyConfiguration.descriptionRequest(target)!, Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD])])
        writes.removeAll(); reads = [baseline, key([0x73])]
        _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: key([0x73]), checkSession: {}, read: { reads.removeFirst() }, voiceState: { 2 }, write: { writes.append($0) })
        XCTAssertEqual(writes, [OrdinaryKeyConfiguration.actionRequest(key([0x73]))!, Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD])])
    }
    @MainActor
    func testNoOpAndConcurrentChangeNeverWrite() async throws {
        let baseline = key()
        _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: baseline, checkSession: {}, read: { baseline }, voiceState: { 2 }, write: { _ in XCTFail("no-op") })
        do {
            _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: key([0x73]), checkSession: {}, read: { self.key([0x28]) }, voiceState: { 2 }, write: { _ in XCTFail("conflict") })
            XCTFail("external edit")
        } catch { XCTAssertEqual(error as? ConfirmedOrdinaryKeySetting.Failure, .changedSinceRead) }
    }
    @MainActor
    func testVoicePresetCannotBeImplicitlySuppressed() async {
        for state: UInt8 in [0, 1, 2, 5] {
            let baseline = key(index: 0), target = key([0x6D], index: 0)
            do {
                _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {}, read: { baseline }, voiceState: { state }, write: { _ in XCTFail("no Voice or suppress writes") })
                XCTFail("preset must protect Voice")
            } catch { XCTAssertEqual(error as? ConfirmedOrdinaryKeySetting.Failure, .voicePresetOwnsKey) }
        }
    }
    @MainActor
    func testVoiceDescriptionDoesNotNeedHandoffAndSuppressedActionCanChange() async throws {
        let baseline = key(index: 0), desc = key(description: "Voice", index: 0)
        var reads = [baseline, desc]
        _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: desc, checkSession: {}, read: { reads.removeFirst() }, voiceState: { XCTFail("description only"); return 2 }, write: { _ in })
        let target = key([0x6D], index: 0); reads = [baseline, target]
        _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {}, read: { reads.removeFirst() }, voiceState: { 3 }, write: { _ in })
    }
    @MainActor
    func testPartialWriteFailureDoesNotSaveOrClaimRollback() async {
        let baseline = key(), target = key([0x73], description: "Test")
        var writes = 0, reads = 0
        do {
            _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {}, read: { reads += 1; return baseline }, voiceState: { 2 }, write: { _ in
                writes += 1; if writes == 2 { throw CancellationError() }
            })
            XCTFail("partial failure")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writes, 2); XCTAssertEqual(reads, 1)
    }
    @MainActor
    func testSaveFailureAndMismatchDoNotConfirm() async {
        let baseline = key(), target = key([0x73])
        var reads = 0
        do {
            _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {}, read: { reads += 1; return baseline }, voiceState: { 2 }, write: { frame in if frame[2] == 4 { throw CancellationError() } })
            XCTFail("save failure")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
        do {
            _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {}, read: { baseline }, voiceState: { 2 }, write: { _ in })
            XCTFail("ACK is not success")
        } catch { XCTAssertEqual(error as? ConfirmedOrdinaryKeySetting.Failure, .mismatch) }
    }
    @MainActor
    func testHandoffBetweenFieldsAndInvalidTargetsStop() async {
        let baseline = key(), target = key([0x73], description: "Test")
        var valid = true, writes = 0
        do {
            _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: { if !valid { throw CancellationError() } }, read: { baseline }, voiceState: { 2 }, write: { _ in writes += 1; valid = false })
            XCTFail("replacement session")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writes, 1)
        do {
            _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: key([0x28], index: 2), checkSession: {}, read: { XCTFail("invalid target must not read"); return baseline }, voiceState: { 2 }, write: { _ in XCTFail("invalid target") })
            XCTFail("wrong key")
        } catch { XCTAssertEqual(error as? ConfirmedOrdinaryKeySetting.Failure, .invalidValue) }
    }
}
