import XCTest
@testable import AhaKeyConfigShared

final class WS3ResourceTransferProgressTests: XCTestCase {
    func testRateAndRemainingUseActualPaddedWireBytes() throws {
        let value = WS3ResourceTransferProgress(completedBytes: 34_416, totalBytes: 344_064, elapsedSeconds: 60)
        XCTAssertEqual(try XCTUnwrap(value.bytesPerSecond), 573.6, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(value.estimatedRemainingSeconds), 539.8326, accuracy: 0.01)
    }
    func testWarmupAndInvalidClocksCannotClaimAFalseSpeed() {
        for time in [0.0, 0.5, -.infinity, .infinity, .nan] {
            let value = WS3ResourceTransferProgress(completedBytes: 48, totalBytes: 100, elapsedSeconds: time)
            XCTAssertNil(value.bytesPerSecond); XCTAssertNil(value.estimatedRemainingSeconds)
        }
    }
    func testCompletionAndBounds() {
        let value = WS3ResourceTransferProgress(completedBytes: 110, totalBytes: 100, elapsedSeconds: 5)
        XCTAssertEqual(value.completedBytes, 100); XCTAssertEqual(value.estimatedRemainingSeconds, 0)
        let zero = WS3ResourceTransferProgress(completedBytes: -5, totalBytes: -1, elapsedSeconds: 10)
        XCTAssertEqual(zero.completedBytes, 0); XCTAssertNil(zero.bytesPerSecond); XCTAssertNil(zero.estimatedRemainingSeconds)
    }
}
