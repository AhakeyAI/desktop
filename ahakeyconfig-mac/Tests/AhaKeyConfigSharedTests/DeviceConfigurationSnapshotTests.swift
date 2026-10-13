import XCTest
@testable import AhaKeyConfigShared

final class DeviceConfigurationSnapshotTests: XCTestCase {
    func testHandoffClearsFactsAndRejectsLateResults() {
        var snapshot = DeviceConfigurationSnapshot(generation: 1)
        snapshot.recordStandby(30, generation: 1)
        snapshot.recordVoice(2, generation: 1)
        snapshot.reset(generation: 2)
        snapshot.recordStandby(120, generation: 1)
        snapshot.recordKey(.tooLarge, mode: 0, index: 0, generation: 1)
        snapshot.recordFailure(.voice, message: "late error", generation: 1)
        XCTAssertNil(snapshot.standbyMinutes)
        XCTAssertNil(snapshot.voiceOnboardingState)
        XCTAssertTrue(snapshot.keys.isEmpty)
        XCTAssertTrue(snapshot.failures.isEmpty)
    }

    func testPartialFailureDoesNotReplaceOtherFactsOrInventDefaults() {
        var snapshot = DeviceConfigurationSnapshot(generation: 3)
        snapshot.recordStandby(60, generation: 3)
        snapshot.recordVoice(2, generation: 3)
        snapshot.recordKey(.tooLarge, mode: 1, index: 2, generation: 3)
        snapshot.recordFailure(.voice, message: "invalid response", generation: 3)
        XCTAssertEqual(snapshot.standbyMinutes, 60)
        XCTAssertNil(snapshot.voiceOnboardingState)
        XCTAssertEqual(snapshot.keys[.key(mode: 1, index: 2)], .tooLarge)
        XCTAssertNil(snapshot.keys[.key(mode: 0, index: 0)])
        XCTAssertEqual(snapshot.failures[.voice], "invalid response")
        snapshot.recordVoice(3, generation: 3)
        XCTAssertNil(snapshot.failures[.voice])
    }

    func testUnknownBinaryActionIsPreservedWithoutEditingConversion() {
        let value = OrdinaryKeyReadback(mode: 0, keyIndex: 3, actionType: 0xFE,
                                       action: Data([0xCC, 0xDD]), description: Data([0xFF]))
        var snapshot = DeviceConfigurationSnapshot(generation: 4)
        snapshot.recordKey(.value(value), mode: 0, index: 3, generation: 4)
        XCTAssertEqual(snapshot.keys[.key(mode: 0, index: 3)], .value(value))
        XCTAssertFalse(value.isKnownEditableAction)
    }

    func testWS2AndUnknownProfilesCannotReachLegacyWriteCommands() {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        for p: FirmwareCapabilityProfile? in [nil, profile] {
            for command: UInt8 in [0x04, 0x73, 0x92, 0x95, 0x96, 0x97] {
                XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, command, 3, 0xCC, 0xDD]), profile: p))
            }
            XCTAssertTrue(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0, 0xCC, 0xDD]), profile: p))
        }
        XCTAssertTrue(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x96, 0xCC, 0xDD]), profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x96, 0xCC, 0xDD]), profile: nil))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x92, 1, 0xCC, 0xDD]), profile: .legacyAfterStatusReadback()))
    }
}
