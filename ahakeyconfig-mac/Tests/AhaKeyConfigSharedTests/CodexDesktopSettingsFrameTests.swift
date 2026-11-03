import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CodexDesktopSettingsFrameTests: XCTestCase {
    private func fixture(settings: [String: Any] = ["approvalPolicy": "on-request", "permissions": ":workspace"]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "sourceClientId": "owner", "unrelated": ["text": "DO_NOT_RETAIN"],
            "params": ["hostId": "local", "conversationId": "thread", "change": [
                "type": "snapshot", "conversationState": ["id": "thread", "messages": ["DO_NOT_RETAIN"],
                    "latestThreadSettings": settings.merging(["model": "DO_NOT_RETAIN"]) { old, _ in old }]]]
        ])
    }

    private func read(_ data: Data, maximumRequested: ((Int) -> Void)? = nil) throws -> [String: Any] {
        var offset = 0
        return try CodexDesktopSettingsFrame.read(length: UInt32(data.count)) { count in
            maximumRequested?(count)
            let next = min(data.count, offset + count)
            defer { offset = next }
            return data.subdata(in: offset..<next)
        }
    }

    private func settings(_ frame: [String: Any]) throws -> [String: Any] {
        let params = try XCTUnwrap(frame["params"] as? [String: Any])
        let change = try XCTUnwrap(params["change"] as? [String: Any])
        let state = try XCTUnwrap(change["conversationState"] as? [String: Any])
        return try XCTUnwrap(state["latestThreadSettings"] as? [String: Any])
    }

    func testProjectsOnlyOwnerAndPermissionFields() throws {
        let frame = try read(fixture())
        XCTAssertEqual(frame["sourceClientId"] as? String, "owner")
        XCTAssertEqual(frame["version"] as? Int, 11)
        XCTAssertEqual(try settings(frame)["permissions"] as? String, ":workspace")
        let encoded = try JSONSerialization.data(withJSONObject: frame)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("DO_NOT_RETAIN"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("messages"))
    }

    func testRetainsCustomSandboxAndStructuredApprovalBaseline() throws {
        let expected: [String: Any] = ["approvalPolicy": ["reject": ["sandbox_approval": false]],
            "sandboxPolicy": ["type": "workspaceWrite", "writableRoots": ["/tmp/项目", "/tmp/assets"], "networkAccess": false]]
        let actual = try settings(read(fixture(settings: expected)))
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
            try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]))
        _ = try CodexDesktopSessionBridge.Settings(encoded: JSONSerialization.data(withJSONObject: actual))
    }

    func testUTF8AndEscapesAcrossFixedBufferBoundary() throws {
        let prefix = Data("{\"ignored\":\"".utf8)
        let rest = try fixture().dropFirst()
        for shift in 0..<10 {
            var data = prefix
            data.append(Data(repeating: 120, count: CodexDesktopSettingsFrame.chunkSize - prefix.count - shift))
            data.append(Data("汉😀\\\"end\",".utf8)); data.append(rest)
            let frame = try read(data)
            XCTAssertEqual(try settings(frame)["permissions"] as? String, ":workspace", "shift=\(shift)")
        }
    }

    func testRejectsMalformedDiscardedValues() {
        let malformed = [
            #"{"ignored":"\x"}"#, #"{"ignored":"\uD800"}"#, #"{"ignored":"\uDC00"}"#,
            #"{"ignored":[1,]}"#, #"{"ignored":{"a":true,}}"#, #"{"ignored":01}"#,
            #"{"ignored":1.}"#, #"{"ignored":1e+}"#, #"{"ignored":tru}"#, #"{"ignored":"unterminated}"#
        ]
        for text in malformed {
            XCTAssertThrowsError(try read(Data(text.utf8)), text)
        }
        for bytes: [UInt8] in [[0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE4, 0x22]] {
            let data = Data("{\"ignored\":\"".utf8) + Data(bytes) + Data("\"}".utf8)
            XCTAssertThrowsError(try read(data))
        }
    }

    func testBoundsRetainedMetadataButNotDiscardedConversationBytes() throws {
        let padding = String(repeating: "x", count: CodexDesktopSettingsFrame.retainedLimit + 1)
        let largeSelected = try JSONSerialization.data(withJSONObject: ["sourceClientId": padding])
        XCTAssertThrowsError(try read(largeSelected))
        let discarded = try JSONSerialization.data(withJSONObject: ["ignored": padding, "type": "broadcast"])
        var largestRead = 0
        let frame = try read(discarded) { largestRead = max(largestRead, $0) }
        XCTAssertEqual(frame["type"] as? String, "broadcast")
        XCTAssertLessThanOrEqual(largestRead, 65_536)
    }

    func testRejectsTruncatedReadAndPropagatesDeadlineWithoutHeaderSizedAllocation() {
        XCTAssertThrowsError(try CodexDesktopSettingsFrame.read(length: 100) { _ in Data([123]) })
        XCTAssertThrowsError(try CodexDesktopSettingsFrame.read(length: UInt32.max) { count in
            XCTAssertEqual(count, 65_536)
            throw CodexDesktopSessionBridge.BridgeError.timedOut
        }) { XCTAssertEqual($0 as? CodexDesktopSessionBridge.BridgeError, .timedOut) }
    }

    func testRejectsExcessiveDepthAndTrailingFrames() {
        let deep = "{\"ignored\":" + String(repeating: "[", count: 600) + "0" + String(repeating: "]", count: 600) + "}"
        for text in [deep, "{}{}", "[]", "{\"ignored\":true} trailing"] {
            XCTAssertThrowsError(try read(Data(text.utf8)))
        }
        XCTAssertThrowsError(try CodexDesktopSettingsFrame.read(length: 0) { _ in XCTFail("Empty frame must not read"); return Data() })
    }

    func testLookalikeFieldsOutsideTheVerifiedPathAreDiscarded() throws {
        let text = #"{"type":"broadcast","method":"wrong-method","version":11,"sourceClientId":"wrong-owner","ignored":{"sourceClientId":"owner","params":{"change":{"conversationState":{"latestThreadSettings":{"approvalPolicy":"never","permissions":":danger-full-access"}}}}},"params":{"hostId":"local","conversationId":"thread","change":{"type":"snapshot","conversationState":{"id":"thread","latestThreadSettings":{"approvalPolicy":"on-request","permissions":":workspace"}}}}}"#
        let frame = try read(Data(text.utf8))
        XCTAssertEqual(frame["sourceClientId"] as? String, "wrong-owner")
        XCTAssertEqual(frame["method"] as? String, "wrong-method")
        XCTAssertEqual(try settings(frame)["permissions"] as? String, ":workspace")
        XCTAssertNil(frame["ignored"])
    }
}
