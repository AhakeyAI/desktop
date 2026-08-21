import XCTest
@testable import AhaKeyConfigShared

final class WriteResultAlertPolicyTests: XCTestCase {
    func testCompleteEditingExitsAfterPartialWriteResult() {
        XCTAssertTrue(
            WriteResultAlertPolicy.shouldExitEditing(for: .completeEditing)
        )
    }

    func testCompleteEditingExitsAfterFailedWriteResult() {
        XCTAssertTrue(
            WriteResultAlertPolicy.shouldExitEditing(for: .completeEditing)
        )
    }

    func testContinueEditingKeepsInspectorOpen() {
        XCTAssertFalse(
            WriteResultAlertPolicy.shouldExitEditing(for: .continueEditing)
        )
    }

    func testLegacyDefaultPictureResultLeadsWithSuccessAndCallsTaskPicturesOptional() {
        XCTAssertEqual(
            AhaKeyDeviceWriteResultMessage.taskPicturesUnsupported(defaultPictureUpdated: true),
            "写入成功：默认图片设置已更新，键位与灯效已写入。旧版固件不支持任务状态动图，该可选功能已跳过。"
        )
    }

    func testLegacyWriteWithoutDefaultPictureUpdateDoesNotClaimItWasWritten() {
        XCTAssertEqual(
            AhaKeyDeviceWriteResultMessage.taskPicturesUnsupported(defaultPictureUpdated: false),
            "写入成功：键位与灯效已写入。当前固件不支持任务状态动图，该可选功能已跳过。"
        )
    }
}
