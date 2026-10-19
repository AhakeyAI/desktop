import XCTest
@testable import AhaKeyConfigShared

final class ConfigurationCancellationTests: XCTestCase {
    @MainActor
    func testAlreadyCancelledModeAndStandbyDoNotReadOrWriteEvenWithPassiveSessionCheck() async {
        let task = Task {
            do {
                _ = try await ConfirmedModeChange.run(target: 1, checkSession: {}, readMode: { XCTFail("read after cancellation"); return 0 }, writeMode: { _ in XCTFail("write after cancellation") })
                XCTFail("mode succeeded after cancellation")
            } catch { XCTAssertTrue(error is CancellationError) }
            do {
                _ = try await ConfirmedStandbySetting.run(target: 30, checkSession: {}, read: { XCTFail("read after cancellation"); return 60 }, write: { _ in XCTFail("write after cancellation") })
                XCTFail("standby succeeded after cancellation")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        task.cancel()
        await task.value
    }
    private func key(_ usage: UInt8) -> OrdinaryKeyReadback {
        .init(mode: 0, keyIndex: 1, actionType: 0x73, action: Data([usage]), description: Data("Key".utf8))
    }
    @MainActor
    func testCancellationAfterActionAckCannotSendDescriptionOrSave() async {
        var writes: [Data] = []
        let baseline = key(0x28)
        let target = OrdinaryKeyReadback(mode: 0, keyIndex: 1, actionType: 0x73, action: Data([0x29]), description: Data("New".utf8))
        let task = Task {
            do {
                _ = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {}, read: { baseline }, voiceState: { 3 }, write: { request in
                    writes.append(request)
                    withUnsafeCurrentTask { $0?.cancel() }
                })
                XCTFail("cancelled partial write succeeded")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertEqual(writes, [OrdinaryKeyConfiguration.actionRequest(target)!])
    }
    @MainActor
    func testCancellationAfterStandbyAckDoesNotReportUnverifiedSuccess() async {
        var reads = 0
        let task = Task {
            do {
                _ = try await ConfirmedStandbySetting.run(target: 30, checkSession: {}, read: { reads += 1; return 60 }, write: { _ in withUnsafeCurrentTask { $0?.cancel() } })
                XCTFail("cancelled setting succeeded")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertEqual(reads, 1)
    }
    @MainActor
    func testCancelledVoiceCannotPrepareTheAppOrTouchConsumer() async {
        let baseline = VoiceHandoffSnapshot(onboardingState: 2, keys: (0..<4).map {
            .init(mode: UInt8($0), keyIndex: 0, actionType: 0x73, action: Data([0xE7]), description: Data())
        })
        let task = Task {
            do {
                _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: { XCTFail("permissions after cancellation") }, read: { XCTFail("read after cancellation"); return baseline }, prepareHost: { XCTFail("App takeover after cancellation") }, write: { _ in XCTFail("Consumer changed after cancellation") })
                XCTFail("cancelled takeover succeeded")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        task.cancel()
        await task.value
    }
    @MainActor
    func testCancellationAfterLeverAckStopsReadback() async {
        let factory: [SideSwitchReadback.Position] = [.init(bindType: 0, action: Data()), .init(bindType: 1, action: Data())]
        let target: [SideSwitchReadback.Position] = [.init(bindType: 2, action: Data()), factory[1]]
        var reads = 0
        let task = Task {
            do {
                _ = try await ConfirmedSideSwitchSetting.run(baseline: factory, target: target, checkSession: {}, read: {
                    reads += 1; return .init(physicalState: 1, positions: factory)
                }, write: { _ in withUnsafeCurrentTask { $0?.cancel() } })
                XCTFail("cancelled lever binding succeeded")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertEqual(reads, 1)
    }
    @MainActor
    func testCancellationAfterVoiceStageSaveCannotSuppressConsumer() async {
        let baseline = VoiceHandoffSnapshot(onboardingState: 2, keys: (0..<4).map {
            .init(mode: UInt8($0), keyIndex: 0, actionType: 0x73, action: Data([0xE7]), description: Data())
        })
        var writes: [UInt8] = []
        let task = Task {
            do {
                _ = try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {}, checkHostReady: {}, read: { baseline }, prepareHost: {}, write: { frame in
                    writes.append(frame[2])
                    if frame[2] == 4 { withUnsafeCurrentTask { $0?.cancel() } }
                })
                XCTFail("cancelled handoff succeeded")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertEqual(writes, [0x73, 0x73, 0x73, 0x73, 4])
        XCTAssertFalse(writes.contains(0x96))
    }
}
