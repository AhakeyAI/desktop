import XCTest
@testable import AhaKeyConfigShared

final class ConfirmedVoiceHandoffTests: XCTestCase {
    private func snapshot(_ state: UInt8 = 2, f18: Bool = false) -> VoiceHandoffSnapshot {
        .init(onboardingState: state, keys: (0..<4).map { mode in
            .init(mode: UInt8(mode), keyIndex: 0, actionType: 0x73, action: Data([f18 || mode % 2 == 1 ? 0x6D : 0xE7]), description: Data("Voice\(mode)".utf8))
        })
    }
    func testGrantOnlyPermitsFourF18ActionsSaveAndSuppress() {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        for key in snapshot().desktopBindings {
            let request = OrdinaryKeyConfiguration.actionRequest(key)!
            XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .voiceHandoff))
            var otherKey = request; otherKey[5] = 1
            XCTAssertFalse(ConfigurationCommandPolicy.permits(otherKey, profile: profile, confirmedWrite: .voiceHandoff))
            var otherAction = request; otherAction[6] = 0xE7
            XCTAssertFalse(ConfigurationCommandPolicy.permits(otherAction, profile: profile, confirmedWrite: .voiceHandoff))
        }
        XCTAssertTrue(ConfigurationCommandPolicy.permits(ConfirmedVoiceHandoff.suppressRequest, profile: profile, confirmedWrite: .voiceHandoff))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(ConfirmedVoiceHandoff.suppressRequest, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(ConfirmedVoiceHandoff.suppressRequest, profile: profile, confirmedWrite: .ordinaryKey))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(ConfirmedVoiceHandoff.suppressRequest, profile: nil, confirmedWrite: .voiceHandoff))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x96, 2, 0xCC, 0xDD]), profile: profile, confirmedWrite: .voiceHandoff))
    }
    @MainActor
    func testStageAllModesBeforeGlobalSuppressAndConfirm() async throws {
        let baseline = snapshot(), staged = snapshot(f18: true), final = snapshot(3, f18: true)
        var reads = [baseline, staged, final], events: [String] = []
        let result = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: {
            events.append("read"); return reads.removeFirst()
        }, prepareHost: { events.append("host") }, write: { frame in
            events.append(frame[2] == 0x73 ? "key\(frame[4])" : "cmd\(frame[2])")
        })
        XCTAssertEqual(result, final)
        XCTAssertEqual(events, ["read", "host", "key0", "key2", "cmd4", "read", "cmd150", "read"])
        XCTAssertEqual(result.keys.map(\.description), baseline.keys.map(\.description))
    }
    @MainActor
    func testAlreadyPreparedDesktopChangesHostOnlyWithoutHardwareWrites() async throws {
        let baseline = snapshot(3, f18: true)
        var preparations = 0
        let result = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: { baseline }, prepareHost: { preparations += 1 }, write: { _ in XCTFail("no hardware write") })
        XCTAssertTrue(result.isDesktopF18Confirmed); XCTAssertEqual(preparations, 1)
    }
    @MainActor
    func testHostReadinessAndBaselineConflictPrecedePreparation() async {
        let baseline = snapshot()
        do {
            _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: { throw ConfirmedVoiceHandoff.Failure.hostNotReady }, read: { XCTFail("not ready"); return baseline }, prepareHost: { XCTFail("not ready") }, write: { _ in XCTFail("not ready") })
            XCTFail("not ready")
        } catch { XCTAssertEqual(error as? ConfirmedVoiceHandoff.Failure, .hostNotReady) }
        do {
            _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: { self.snapshot(1) }, prepareHost: { XCTFail("conflict") }, write: { _ in XCTFail("conflict") })
            XCTFail("conflict")
        } catch { XCTAssertEqual(error as? ConfirmedVoiceHandoff.Failure, .changedSinceRead) }
    }
    @MainActor
    func testPartialKeyOrSaveFailureNeverSuppresses() async {
        let baseline = snapshot()
        for failCommand: UInt8 in [0x73, 4] {
            var reads = 0, writes: [UInt8] = []
            do {
                _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: { reads += 1; return baseline }, prepareHost: {}, write: { frame in
                    writes.append(frame[2]); if frame[2] == failCommand { throw CancellationError() }
                })
                XCTFail("failed stage")
            } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(writes.contains(0x96)); XCTAssertEqual(reads, 1)
        }
    }
    @MainActor
    func testStagedBindingMismatchOrOwnershipChangeNeverSuppresses() async {
        let baseline = snapshot()
        for bad in [baseline, snapshot(1, f18: true)] {
            var reads = [baseline, bad]
            do {
                _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: { reads.removeFirst() }, prepareHost: {}, write: { frame in XCTAssertNotEqual(frame[2], 0x96) })
                XCTFail("bad stage")
            } catch { XCTAssertNotNil(error as? ConfirmedVoiceHandoff.Failure) }
        }
    }
    @MainActor
    func testSuppressAckWithoutOwnershipReadbackIsNotSuccess() async {
        let baseline = snapshot(f18: true)
        var reads = [baseline, baseline]
        do {
            _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: { reads.removeFirst() }, prepareHost: {}, write: { frame in XCTAssertEqual(frame, ConfirmedVoiceHandoff.suppressRequest) })
            XCTFail("ACK alone")
        } catch { XCTAssertEqual(error as? ConfirmedVoiceHandoff.Failure, .ownershipMismatch) }
    }
    @MainActor
    func testDisconnectAfterSaveCannotSuppressNewConnection() async {
        let baseline = snapshot()
        var connected = true, reads = 0
        do {
            _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: { if !connected { throw CancellationError() } }, checkHostReady: {}, read: { reads += 1; return baseline }, prepareHost: {}, write: { frame in
                XCTAssertNotEqual(frame[2], 0x96); if frame[2] == 4 { connected = false }
            })
            XCTFail("disconnected")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }
    @MainActor
    func testInvalidFourModeSnapshotNeverReadsOrPrepares() async {
        let baseline = VoiceHandoffSnapshot(onboardingState: 2, keys: Array(snapshot().keys.prefix(3)))
        do {
            _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: { XCTFail("incomplete"); return baseline }, prepareHost: { XCTFail("incomplete") }, write: { _ in XCTFail("incomplete") })
            XCTFail("incomplete")
        } catch { XCTAssertEqual(error as? ConfirmedVoiceHandoff.Failure, .invalidSnapshot) }
    }
}
