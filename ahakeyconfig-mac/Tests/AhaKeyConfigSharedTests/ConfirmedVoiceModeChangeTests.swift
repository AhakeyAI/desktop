import XCTest
@testable import AhaKeyConfigShared

final class ConfirmedVoiceModeChangeTests: XCTestCase {
    private func snapshot(_ state: UInt8 = 2) -> VoiceHandoffSnapshot {
        .init(onboardingState: state, keys: (0..<4).map {
            .init(mode: UInt8($0), keyIndex: 0, actionType: 0x73, action: Data([0x3A + UInt8($0)]), description: Data("Voice\($0)".utf8))
        })
    }
    private func replacing(_ value: VoiceHandoffSnapshot, with target: OrdinaryKeyReadback, state: UInt8? = nil) -> VoiceHandoffSnapshot {
        var keys = value.keys; keys[Int(target.mode)] = target
        return .init(onboardingState: state ?? value.onboardingState, keys: keys)
    }
    private var target: OrdinaryKeyReadback {
        .init(mode: 2, keyIndex: 0, actionType: 0x73, action: Data([0xE3, 0x28]), description: Data("Custom".utf8))
    }

    @MainActor
    func testChangesOnlySelectedKeyBeforeGlobalExitAndChecksAllBindings() async throws {
        let before = snapshot(), staged = replacing(snapshot(), with: target)
        let final = replacing(staged, with: target, state: 3)
        var reads = [before, staged, final], events: [String] = [], frames: [Data] = []
        let result = try await ConfirmedVoiceModeChange.run(baseline: before, target: target,
            checkSession: {}, checkHostReady: {}, read: { events.append("read"); return reads.removeFirst() },
            validateCurrentKey: { _ in }, prepareHost: { events.append("host") }, write: {
                frames.append($0); events.append($0[2] == 0x73 ? "key\($0[4])" : "cmd\($0[2])")
            })
        XCTAssertEqual(result, final)
        XCTAssertEqual(events, ["read", "key2", "key2", "cmd4", "read", "host", "cmd150", "read"])
        XCTAssertTrue(frames.filter { $0[2] == 0x73 }.allSatisfy { $0[4] == 2 && $0[5] == 0 })
        for mode in [0, 1, 3] { XCTAssertEqual(final.keys[mode], before.keys[mode]) }
    }

    @MainActor
    func testUnchangedKeyStillRequiresGlobalConfirmationAndNoRebinds() async throws {
        let before = snapshot(), final = VoiceHandoffSnapshot(onboardingState: 3, keys: before.keys)
        var reads = [before, final], frames: [Data] = [], prepared = false
        _ = try await ConfirmedVoiceModeChange.run(baseline: before, target: before.keys[2],
            checkSession: {}, checkHostReady: {}, read: { reads.removeFirst() }, validateCurrentKey: { _ in }, prepareHost: { prepared = true }, write: {
                XCTAssertTrue(prepared); frames.append($0)
            })
        XCTAssertEqual(frames, [ConfirmedVoiceHandoff.suppressRequest])
    }

    @MainActor
    func testOrdinaryRouteRecoveryArmsHostBeforeChangingPhysicalTrigger() async throws {
        let before = snapshot(3), staged = replacing(before, with: target)
        var reads = [before, staged], prepared = false
        _ = try await ConfirmedVoiceModeChange.run(baseline: before, target: target,
            checkSession: {}, checkHostReady: {}, read: { reads.removeFirst() }, validateCurrentKey: { _ in }, prepareHost: { prepared = true }, write: {
                XCTAssertTrue(prepared); XCTAssertNotEqual($0[2], 0x96)
            })
    }

    @MainActor
    func testConflictOrReadinessFailureNeverPreparesOrWrites() async {
        let before = snapshot()
        do {
            _ = try await ConfirmedVoiceModeChange.run(baseline: before, target: target,
                checkSession: {}, checkHostReady: {}, read: { self.snapshot(3) },
                validateCurrentKey: { _ in }, prepareHost: { XCTFail("conflict") }, write: { _ in XCTFail("conflict") })
            XCTFail("must reject")
        } catch { XCTAssertEqual(error as? ConfirmedVoiceHandoff.Failure, .changedSinceRead) }
        do {
            _ = try await ConfirmedVoiceModeChange.run(baseline: before, target: target,
                checkSession: {}, checkHostReady: { throw CancellationError() }, read: { XCTFail("not ready"); return before },
                validateCurrentKey: { _ in }, prepareHost: { XCTFail("not ready") }, write: { _ in XCTFail("not ready") })
            XCTFail("must reject")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor
    func testOtherModeChangesDuringStagePreventGlobalSuppress() async {
        let before = snapshot()
        var keys = replacing(before, with: target).keys
        keys[0] = .init(mode: 0, keyIndex: 0, actionType: 0x73, action: Data([0x28]), description: Data())
        var reads = [before, VoiceHandoffSnapshot(onboardingState: 2, keys: keys)]
        do {
            _ = try await ConfirmedVoiceModeChange.run(baseline: before, target: target,
                checkSession: {}, checkHostReady: {}, read: { reads.removeFirst() },
                validateCurrentKey: { _ in }, prepareHost: { XCTFail("stage mismatch") }, write: { XCTAssertNotEqual($0[2], 0x96) })
            XCTFail("must reject")
        } catch { XCTAssertEqual(error as? ConfirmedVoiceHandoff.Failure, .bindingsMismatch) }
    }

    @MainActor
    func testFailedKeyOrPersistenceNeverDisablesConsumer() async {
        for fail: UInt8 in [0x73, 0x04] {
            let before = snapshot()
            do {
                _ = try await ConfirmedVoiceModeChange.run(baseline: before, target: target,
                    checkSession: {}, checkHostReady: {}, read: { before }, validateCurrentKey: { _ in }, prepareHost: { XCTFail("failed stage") }, write: {
                        XCTAssertNotEqual($0[2], 0x96)
                        if $0[2] == fail { throw CancellationError() }
                    })
                XCTFail("must reject")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    @MainActor
    func testSuppressAckDoesNotReplaceOwnershipReadback() async {
        let before = snapshot(), staged = replacing(before, with: target)
        var reads = [before, staged, staged]
        do {
            _ = try await ConfirmedVoiceModeChange.run(baseline: before, target: target,
                checkSession: {}, checkHostReady: {}, read: { reads.removeFirst() }, validateCurrentKey: { _ in }, prepareHost: {}, write: { _ in })
            XCTFail("must reject")
        } catch { XCTAssertEqual(error as? ConfirmedVoiceHandoff.Failure, .ownershipMismatch) }
    }
    @MainActor
    func testReadOnlyValidationCannotBeBypassedByConflictConfirmation() async {
        let before = snapshot()
        let readOnly = replacing(before, with: .init(mode: 2, keyIndex: 0, actionType: 0x73,
            action: Data([0x28, 0xE3]), description: Data("Read only".utf8)))
        do {
            _ = try await ConfirmedVoiceModeChange.run(baseline: readOnly, target: target,
                checkSession: {}, checkHostReady: {}, read: { readOnly }, validateCurrentKey: { _ in
                    throw ConfirmedOrdinaryKeySetting.Failure.invalidValue
                }, prepareHost: { XCTFail("read only") }, write: { _ in XCTFail("read only") })
            XCTFail("must reject")
        } catch { XCTAssertEqual(error as? ConfirmedOrdinaryKeySetting.Failure, .invalidValue) }
    }

}
