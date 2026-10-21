import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class WS3DisplayOperationOwnershipTests: XCTestCase {
    private func manager(root: URL) -> AhaKeyBLEManager {
        AhaKeyBLEManager(startServices: false,
            logStore: BLELogStore(verboseLogFileURL: root.appendingPathComponent("verbose.log"), persistentLogFileURL: root.appendingPathComponent("persistent.log")),
            connectionLock: BLEConnectionLock(lockURL: root.appendingPathComponent("owner.lock")),
            ideStateDirectoryURL: root.appendingPathComponent("state"))
    }

    func testOldReadAndPreviewCannotUnlockNewConnectionOperation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for kind: AhaKeyBLEManager.WS3DisplayOperationKind in [.reading, .updating] {
            let host = manager(root: root)
            let entered = expectation(description: "old operation paused")
            var release: CheckedContinuation<Void, Never>?
            let old = Task { @MainActor in
                let ticket = host.beginWS3DisplayOperation(kind)
                defer { host.finishWS3DisplayOperation(ticket) }
                entered.fulfill()
                await withCheckedContinuation { release = $0 }
            }
            await fulfillment(of: [entered], timeout: 2)
            XCTAssertTrue(host.isConfigurationOperationInProgress)
            // Exercise the real power-off -> invalidation -> generation reset.
            host.handleBluetoothPoweredOff()
            XCTAssertFalse(host.isConfigurationOperationInProgress)
            let fresh = host.beginWS3DisplayOperation(kind)
            release?.resume(); await old.value
            XCTAssertTrue(host.isConfigurationOperationInProgress)
            XCTAssertEqual(host.isReadingWS3Display, kind == .reading)
            XCTAssertEqual(host.isUpdatingWS3Display, kind == .updating)
            host.finishWS3DisplayOperation(fresh)
            XCTAssertFalse(host.isConfigurationOperationInProgress)
        }
    }

    func testCompletedTicketCannotUnlockLaterOperationOnSameConnection() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = manager(root: root)
        let finished = host.beginWS3DisplayOperation(.reading)
        host.finishWS3DisplayOperation(finished)
        let current = host.beginWS3DisplayOperation(.updating)
        host.finishWS3DisplayOperation(finished)
        XCTAssertTrue(host.isUpdatingWS3Display)
        host.finishWS3DisplayOperation(current)
        XCTAssertFalse(host.isConfigurationOperationInProgress)
    }
}
