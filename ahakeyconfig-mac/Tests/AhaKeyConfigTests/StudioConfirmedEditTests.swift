import XCTest
@testable import AhaKeyConfig

@MainActor
final class StudioConfirmedEditTests: XCTestCase {
    private final class Device {
        var identity = "A"
        var generation: UInt64 = 1
        var revision: UInt64 = 1
        var released = 0
        var writes = 0
        @MainActor func session() -> StudioInspectorSession {
            .init(access: .init(begin: { self.revision }, isCurrent: { $0 == self.revision },
                isReady: { true }, generation: { self.generation }, deviceID: { self.identity },
                release: { _ in self.released += 1 }, pause: {}))
        }
    }
    func testReconnectUsesFreshFactAndConflictsBeforeWriting() async throws {
        let device = Device(); device.generation = 9
        let result = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
            session: device.session(), read: { context in XCTAssertEqual(context.generation, 9); return 120 },
            write: { _, _ in device.writes += 1; return 30 })
        XCTAssertEqual(result, .conflict(.init(deviceID: "A", value: 120)))
        XCTAssertEqual(device.writes, 0); XCTAssertEqual(device.released, 1)
    }
    func testNoOpDoesNotWriteAndReturnsLease() async throws {
        let device = Device()
        let result = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 60,
            session: device.session(), read: { _ in 60 }, write: { _, _ in device.writes += 1; return 60 })
        XCTAssertEqual(result, .saved(.init(deviceID: "A", value: 60), wrote: false))
        XCTAssertEqual(device.writes, 0); XCTAssertEqual(device.released, 1)
    }
    func testOnlyCapturedTargetIsWrittenAfterFreshRead() async throws {
        let device = Device()
        let result = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
            session: device.session(), read: { _ in 60 }, write: { actual, context in
                XCTAssertEqual(actual, 60); XCTAssertEqual(context.deviceID, "A")
                device.writes += 1; return 30
            })
        XCTAssertEqual(result, .saved(.init(deviceID: "A", value: 30), wrote: true))
        XCTAssertEqual(device.writes, 1); XCTAssertEqual(device.released, 1)
    }
    func testChangedDeviceCannotReceiveOldDraft() async {
        let device = Device(); device.identity = "B"
        do {
            _ = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
                session: device.session(), read: { _ in XCTFail("Wrong device"); return 60 },
                write: { _, _ in device.writes += 1; return 30 })
            XCTFail("Expected identity failure")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .deviceChanged) }
        XCTAssertEqual(device.writes, 0); XCTAssertEqual(device.released, 1)
    }
    func testLateWriteResultCannotPublishSuccessAfterGenerationChanges() async {
        let device = Device()
        do {
            _ = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
                session: device.session(), read: { _ in 60 }, write: { _, _ in
                    device.writes += 1; device.generation += 1; return 30
                })
            XCTFail("Expected stale result failure")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .sessionChanged) }
        XCTAssertEqual(device.writes, 1); XCTAssertEqual(device.released, 1)
    }
    func testCancellationBeforeWriteReturnsLease() async {
        let device = Device()
        let task = Task { @MainActor in
            try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
                session: device.session(), read: { _ in throw CancellationError() },
                write: { _, _ in device.writes += 1; return 30 })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(device.writes, 0); XCTAssertEqual(device.released, 1)
    }
    func testMismatchedReadbackDoesNotBecomeSuccess() async {
        let device = Device()
        do {
            _ = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
                session: device.session(), read: { _ in 60 }, write: { _, _ in 120 })
            XCTFail("Expected mismatch")
        } catch { XCTAssertNotNil(error as? StudioConfirmedEdit.Failure) }
        XCTAssertEqual(device.released, 1)
    }
    func testFailedWriteThenMatchingRAMDoesNotConfirmPersistence() async throws {
        let device = Device(); var ram = 60
        do {
            _ = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
                session: device.session(), read: { _ in ram }, write: { _, _ in
                    ram = 30; device.writes += 1; throw CancellationError()
                })
            XCTFail("Expected interrupted write")
        } catch { XCTAssertTrue(error is CancellationError) }
        let result = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: ram), desired: 30,
            requiresPersistence: true, session: device.session(), read: { _ in ram },
            write: { _, _ in XCTFail("No hidden persistence retry"); return 30 })
        XCTAssertEqual(result, .unconfirmed(.init(deviceID: "A", value: 30)))
        XCTAssertEqual(device.writes, 1); XCTAssertEqual(device.released, 2)
    }
    func testReconnectDuringFreshReadStopsBeforeWrite() async {
        let device = Device()
        do {
            _ = try await StudioConfirmedEdit.run(baseline: .init(deviceID: "A", value: 60), desired: 30,
                session: device.session(), read: { _ in device.generation += 1; return 60 },
                write: { _, _ in device.writes += 1; return 30 })
            XCTFail("Expected stale read rejection")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .sessionChanged) }
        XCTAssertEqual(device.writes, 0); XCTAssertEqual(device.released, 1)
    }
}
