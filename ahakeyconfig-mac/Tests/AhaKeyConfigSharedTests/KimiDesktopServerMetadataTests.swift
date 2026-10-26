import XCTest
@testable import AhaKeyConfigShared

final class KimiDesktopServerMetadataTests: XCTestCase {
    private let id = "01" + String(repeating: "A", count: 24)
    private let started: Int64 = 1_800_000_000_000
    private func registration(version: String? = "2.3.2") throws -> KimiDesktopInstanceDiscovery.Registration {
        var object: [String: Any] = ["server_id": id, "pid": 1234, "host": "127.0.0.1", "port": 23456,
                                     "started_at": started, "heartbeat_at": started + 100]
        object["host_version"] = version
        return try XCTUnwrap(KimiDesktopInstanceDiscovery.Registration.parse(
            JSONSerialization.data(withJSONObject: object), filename: id + ".json", nowMilliseconds: started + 200))
    }
    private func body() -> [String: Any] {
        ["server_id": id, "server_version": "2.3.2", "started_at": started,
         "dangerous_bypass_auth": false, "backend": "v2",
         "capabilities": Dictionary(uniqueKeysWithValues:
            ["websocket", "file_upload", "fs_query", "mcp", "tasks", "terminal"].map { ($0, true) })]
    }
    private func parse(_ body: [String: Any], code: Any = 0) throws -> KimiDesktopServerMetadata? {
        KimiDesktopServerMetadata.parse(try JSONSerialization.data(withJSONObject: ["code": code, "data": body]),
                                        expected: try registration())
    }
    func testOfficialShapeBindsServerIdentityAndStartTime() throws {
        let value = try XCTUnwrap(parse(body()))
        XCTAssertEqual(value.serverID, id)
        XCTAssertEqual(value.serverVersion, "2.3.2")
        XCTAssertEqual(value.startedAt, started)
    }
    func testHTTPBusinessFailureAndBooleanCodeCannotBecomeSuccess() throws {
        for code: Any in [false, true, "0", 0.5, 401, 500] {
            XCTAssertNil(try parse(body(), code: code))
        }
    }
    func testAnotherInstanceRestartOrUninspectedVersionFailsBinding() throws {
        for (key, value): (String, Any) in [("server_id", "01" + String(repeating: "B", count: 24)),
                                          ("started_at", started + 1), ("server_version", "2.4.0"),
                                          ("backend", "v1")] {
            var changed = body(); changed[key] = value
            XCTAssertNil(try parse(changed))
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": body()])
        XCTAssertNil(KimiDesktopServerMetadata.parse(data, expected: try registration(version: "2.3.3")))
        XCTAssertNotNil(KimiDesktopServerMetadata.parse(data, expected: try registration(version: nil)))
    }
    func testBypassMissingFlagsAndNumericBooleansAreRejected() throws {
        for value: Any in [true, 0, "false"] {
            var changed = body(); changed["dangerous_bypass_auth"] = value
            XCTAssertNil(try parse(changed))
        }
        var changed = body(); changed.removeValue(forKey: "dangerous_bypass_auth")
        XCTAssertNil(try parse(changed))
        changed = body(); changed["capabilities"] = ["websocket": true]
        XCTAssertNil(try parse(changed))
    }
    func testMalformedAndOversizedResponseFailsClosedWithoutSessionAction() throws {
        let expected = try registration()
        XCTAssertNil(KimiDesktopServerMetadata.parse(Data("not json".utf8), expected: expected))
        XCTAssertNil(KimiDesktopServerMetadata.parse(Data(repeating: 32, count: 65_537), expected: expected))
        var changed = body(); changed["started_at"] = true
        XCTAssertNil(try parse(changed))
    }
}
