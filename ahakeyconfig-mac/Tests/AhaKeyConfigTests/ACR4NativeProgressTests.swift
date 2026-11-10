import XCTest
@testable import AhaKeyConfig
import AhaKeyConfigShared

final class ACR4NativeProgressTests: XCTestCase {
    func testEncodedResourceProgressUsesAcknowledgedBytesInsteadOfRoundedChunks() {
        let progress = AhaKeyBLEManager.OLEDUploadProgress(completedChunks: 2, totalChunks: 30,
            completedFrames: 0, totalFrames: 12,
            transfer: .init(completedBytes: 144, totalBytes: 3784, elapsedSeconds: 2))
        XCTAssertEqual(progress.fractionCompleted, 144.0 / 3784.0, accuracy: 0.000001)
        let legacy = AhaKeyBLEManager.OLEDUploadProgress(completedChunks: 2, totalChunks: 10,
            completedFrames: 0, totalFrames: 1)
        XCTAssertEqual(legacy.fractionCompleted, 0.2)
    }
}
