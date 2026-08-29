import XCTest
@testable import AhaKeyConfig
@testable import AhaKeyConfigShared

final class AhaKeyStudioFailureTextTests: XCTestCase {
    func testFullContextShowsStepOpcodeAndStatus() throws {
        let operation = try makeOperation(
            state: .failedWithPartialCommit,
            messageCode: .configurationDeviceRejected,
            failureContext: .init(
                failedStepID: try AhaKeyRuntimeStepIdentifier("base:mode:0"),
                opcode: 0x97,
                deviceStatus: 3
            )
        )
        let detail = String(
            format: NSLocalizedString("步骤 %@，命令 0x%02X，status=%u", comment: ""),
            "base:mode:0", UInt8(0x97), UInt8(3)
        )
        XCTAssertEqual(
            AhaKeyStudioFailureText.message(for: operation),
            String(
                format: NSLocalizedString("部分完成：Runtime 报告部分步骤未写入（%@）。可再次点击写入重试。", comment: ""),
                detail
            )
        )
    }

    func testPartialFieldsDoNotFabricateMissingOpcodeOrStatus() throws {
        let operation = try makeOperation(
            state: .resumablePartial,
            failureContext: .init(failedStepID: try AhaKeyRuntimeStepIdentifier("resource:img-a"))
        )
        let detail = String(format: NSLocalizedString("步骤 %@", comment: ""), "resource:img-a")
        XCTAssertEqual(
            AhaKeyStudioFailureText.message(for: operation),
            String(
                format: NSLocalizedString("部分完成：Runtime 报告部分步骤未写入（%@）。可再次点击写入重试。", comment: ""),
                detail
            )
        )
        XCTAssertFalse(AhaKeyStudioFailureText.detail(for: operation).contains("0x"))
        XCTAssertFalse(AhaKeyStudioFailureText.detail(for: operation).contains("status="))
    }

    func testMessageCodeOnlyShowsStableCategory() throws {
        let operation = try makeOperation(
            state: .failedWithoutWrites,
            messageCode: .configurationDeviceRejected
        )
        let text = AhaKeyStudioFailureText.message(for: operation)
        XCTAssertEqual(
            text,
            String(
                format: NSLocalizedString("Runtime 写入失败（%@），未提交任何改动。", comment: ""),
                NSLocalizedString("设备拒绝了配置命令", comment: "")
            )
        )
        XCTAssertFalse(text.contains("0x"))
        XCTAssertFalse(text.contains("status="))
        XCTAssertFalse(text.contains("base:mode"))
    }

    func testAllNilKeepsGenericFallback() throws {
        let partial = try makeOperation(state: .failedWithPartialCommit)
        XCTAssertEqual(
            AhaKeyStudioFailureText.message(for: partial),
            String(
                format: NSLocalizedString("部分完成：Runtime 报告部分步骤未写入（%@）。可再次点击写入重试。", comment: ""),
                "—"
            )
        )
        let noWrites = try makeOperation(state: .failedWithoutWrites)
        XCTAssertEqual(
            AhaKeyStudioFailureText.message(for: noWrites),
            String(
                format: NSLocalizedString("Runtime 写入失败（%@），未提交任何改动。", comment: ""),
                "—"
            )
        )
    }

    private func makeOperation(
        state: AhaKeyRuntimeOperationState,
        messageCode: AhaKeyRuntimeEventCode? = nil,
        failureContext: AhaKeyRuntimeOperationFailureContext? = nil
    ) throws -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: state,
            completedSteps: state == .failedWithoutWrites ? 0 : 3,
            totalSteps: 7,
            messageCode: messageCode,
            failureContext: failureContext
        )
    }
}
