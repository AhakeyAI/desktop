import XCTest
@testable import AhaKeyConfig

final class DeviceInfoFirmwareReadbackTests: XCTestCase {
    private let connection = DeviceInfoFirmwareReadback.Connection(connected: true, generation: 7)

    @MainActor
    func testDirectConnectionWaitsForStatusAndExplicitOperationBeforeReadingCatalog() async throws {
        var waits = 0, reads = 0
        var ready = false, busy = true
        let read = try await DeviceInfoFirmwareReadback.run(connection: connection,
            state: { .init(connection: self.connection, statusReady: ready, operationBusy: busy, profileKnown: false) },
            read: { XCTAssertTrue(ready); XCTAssertFalse(busy); reads += 1 },
            wait: { waits += 1; ready = true; if waits == 2 { busy = false } })
        XCTAssertTrue(read)
        XCTAssertEqual(waits, 2)
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testAgentOwnershipNeverStartsDirectRead() async throws {
        var reads = 0
        let agent = DeviceInfoFirmwareReadback.Connection(connected: false, generation: 7)
        let result = try await DeviceInfoFirmwareReadback.run(connection: agent,
            state: { .init(connection: agent, statusReady: true, operationBusy: false, profileKnown: false) },
            read: { reads += 1 })
        XCTAssertFalse(result)
        XCTAssertEqual(reads, 0)
    }

    @MainActor
    func testKnownProfileIsNotRefreshedAndDoesNotInvalidateEditorFacts() async throws {
        var reads = 0
        let result = try await DeviceInfoFirmwareReadback.run(connection: connection,
            state: { .init(connection: self.connection, statusReady: true, operationBusy: false, profileKnown: true) },
            read: { reads += 1 })
        XCTAssertFalse(result)
        XCTAssertEqual(reads, 0)
    }

    @MainActor
    func testReconnectDuringReadinessWaitDoesNotProbeAnotherGeneration() async throws {
        var current = connection
        var reads = 0
        let result = try await DeviceInfoFirmwareReadback.run(connection: connection,
            state: { .init(connection: current, statusReady: false, operationBusy: false, profileKnown: false) },
            read: { reads += 1 }, wait: { current = .init(connected: true, generation: 8) })
        XCTAssertFalse(result)
        XCTAssertEqual(reads, 0)
    }

    @MainActor
    func testReplyAfterConnectionChangesIsNotReportedAsCurrentSuccess() async throws {
        var current = connection
        let result = try await DeviceInfoFirmwareReadback.run(connection: connection,
            state: { .init(connection: current, statusReady: true, operationBusy: false, profileKnown: false) },
            read: { current = .init(connected: false, generation: 8) })
        XCTAssertFalse(result)
    }

    @MainActor
    func testBusyOperationHasBoundedWaitAndNoQuery() async throws {
        var reads = 0, waits = 0
        let result = try await DeviceInfoFirmwareReadback.run(connection: connection,
            state: { .init(connection: self.connection, statusReady: true, operationBusy: true, profileKnown: false) },
            read: { reads += 1 }, wait: { waits += 1 }, maximumWaits: 2)
        XCTAssertFalse(result)
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(waits, 2)
    }

    @MainActor
    func testCancellationDuringWaitDoesNotSendRead() async {
        var reads = 0
        do {
            _ = try await DeviceInfoFirmwareReadback.run(connection: connection,
                state: { .init(connection: self.connection, statusReady: false, operationBusy: false, profileKnown: false) },
                read: { reads += 1 }, wait: { throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 0)
    }

    @MainActor
    func testReadFailurePropagatesWithoutAutomaticRetry() async {
        enum FailedRead: Error { case unavailable }
        var reads = 0
        do {
            _ = try await DeviceInfoFirmwareReadback.run(connection: connection,
                state: { .init(connection: self.connection, statusReady: true, operationBusy: false, profileKnown: false) },
                read: { reads += 1; throw FailedRead.unavailable })
            XCTFail("Expected read failure")
        } catch { XCTAssertTrue(error is FailedRead) }
        XCTAssertEqual(reads, 1)
    }
}
