import XCTest
@testable import AhaKeyConfig
@testable import AhaKeyConfigShared

final class AhaKeyStudioWriteProgressTextTests: XCTestCase {
    func testPrefersBytePercentWhenPresent() throws {
        let operation = AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: .running,
            completedSteps: 0,
            totalSteps: 7,
            completedBytes: 1200,
            totalBytes: 4000,
            currentStepID: try AhaKeyRuntimeStepIdentifier("resource:a")
        )
        let text = AhaKeyStudioWriteProgressText.status(for: operation, elapsedSeconds: 9)
        XCTAssertTrue(text.contains("1200"))
        XCTAssertTrue(text.contains("4000"))
        XCTAssertTrue(text.contains("30%"))
        XCTAssertFalse(text.contains("已用"))
    }

    func testFallsBackToElapsedStepsWhenBytesMissing() throws {
        let operation = AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: .running,
            completedSteps: 0,
            totalSteps: 7
        )
        let text = AhaKeyStudioWriteProgressText.status(for: operation, elapsedSeconds: 4)
        XCTAssertEqual(
            text,
            String(
                format: NSLocalizedString("Runtime 正在上传图片资源（%u/%u，已用 %d 秒）…", comment: ""),
                UInt32(0), UInt32(7), 4
            )
        )
    }

    func testSameByteProgressYieldsIdenticalCopy() throws {
        let operation = AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: .running,
            completedSteps: 0,
            totalSteps: 7,
            completedBytes: 50,
            totalBytes: 100
        )
        XCTAssertEqual(
            AhaKeyStudioWriteProgressText.status(for: operation, elapsedSeconds: 1),
            AhaKeyStudioWriteProgressText.status(for: operation, elapsedSeconds: 8)
        )
    }
}
