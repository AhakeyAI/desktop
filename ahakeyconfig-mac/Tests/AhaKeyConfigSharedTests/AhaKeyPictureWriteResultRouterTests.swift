import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 返工 R2：0x81 写入确认的 session 匹配与裁决。
final class AhaKeyPictureWriteResultRouterTests: XCTestCase {

    private typealias Router = AhaKeyPictureWriteResultRouter

    func testSuccessWithMatchingSession() {
        XCTAssertEqual(
            Router.decide(status: 0, payload: [0x34, 0x12], expectedSession: 0x1234),
            .success
        )
    }

    func testDeviceRejectedKeepsSessionSemantics() {
        XCTAssertEqual(
            Router.decide(status: 1, payload: [0x34, 0x12], expectedSession: 0x1234),
            .deviceRejected
        )
    }

    func testStaleSessionIgnored() {
        XCTAssertEqual(
            Router.decide(status: 0, payload: [0x99, 0x99], expectedSession: 0x1234),
            .ignoreStaleSession(session: 0x9999)
        )
    }

    func testMissingSessionIgnored() {
        XCTAssertEqual(
            Router.decide(status: 0, payload: [], expectedSession: 0x1234),
            .ignoreMissingSession
        )
    }

    func testLegacyNoSessionSkipsMatch() {
        // 0x80 裸写路径（无会话）：不校验 session，仅按 status 裁决
        XCTAssertEqual(Router.decide(status: 0, payload: [], expectedSession: nil), .success)
        XCTAssertEqual(Router.decide(status: 2, payload: [], expectedSession: nil), .deviceRejected)
    }
}
