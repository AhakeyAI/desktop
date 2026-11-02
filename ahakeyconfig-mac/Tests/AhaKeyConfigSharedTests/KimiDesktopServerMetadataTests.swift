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
        ["server_id": id, "server_version": "2.3.2", "started_at": "2027-01-15T08:00:00.250Z",
         "dangerous_bypass_auth": false, "backend": "v2",
         "capabilities": Dictionary(uniqueKeysWithValues:
            ["websocket", "file_upload", "fs_query", "mcp", "tasks", "terminal"].map { ($0, true) })]
    }
    private func parse(_ body: [String: Any], code: Any = 0) throws -> KimiDesktopServerMetadata? {
        KimiDesktopServerMetadata.parse(try JSONSerialization.data(withJSONObject: ["code": code, "data": body]),
                                        expected: try registration(), installedVersion: "1.1.3")
    }
    func testOfficialShapeBindsServerIdentityAndStartTime() throws {
        let value = try XCTUnwrap(parse(body()))
        XCTAssertEqual(value.serverID, id)
        XCTAssertEqual(value.serverVersion, "2.3.2")
        XCTAssertEqual(value.startedAt, started + 250)
    }
    func testInspected240MetadataWithFiveCapabilitiesIsAccepted() throws {
        var changed = body()
        changed["server_version"] = "2.4.0"
        var flags = try XCTUnwrap(changed["capabilities"] as? [String: Bool])
        flags.removeValue(forKey: "terminal")
        changed["capabilities"] = flags
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": changed])
        let value = try XCTUnwrap(KimiDesktopServerMetadata.parse(data, expected: registration(version: "2.4.0"), installedVersion: "1.2.1"))
        XCTAssertEqual(value.serverVersion, "2.4.0")
    }
    func testInspectedContractsCannotMixAppVersionsOrCapabilitySets() throws {
        for (app, server, flags) in [
            ("1.1.3", "2.4.0", ["websocket", "file_upload", "fs_query", "mcp", "tasks"]),
            ("1.2.1", "2.3.2", ["websocket", "file_upload", "fs_query", "mcp", "tasks", "terminal"]),
            ("1.2.1", "2.4.0", ["websocket", "file_upload", "fs_query", "mcp", "tasks", "terminal"]),
            ("1.1.3", "2.3.2", ["websocket", "file_upload", "fs_query", "mcp", "tasks"]),
            ("1.2.2", "2.4.0", ["websocket", "file_upload", "fs_query", "mcp", "tasks"]),
            ("1.2.1", "2.4.1", ["websocket", "file_upload", "fs_query", "mcp", "tasks"])
        ] {
            var changed = body()
            changed["server_version"] = server
            changed["capabilities"] = Dictionary(uniqueKeysWithValues: flags.map { ($0, true) })
            let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": changed])
            XCTAssertNil(KimiDesktopServerMetadata.parse(data, expected: try registration(version: server),
                installedVersion: app), "\(app)/\(server)/\(flags)")
        }
    }
    func test240StillRequiresStrictBooleanCapabilitiesAndRegistryVersion() throws {
        let flags = ["websocket", "file_upload", "fs_query", "mcp", "tasks"]
        for flag in flags {
            for invalid: Any in [false, 1, "true", NSNull()] {
                var changed = body()
                changed["server_version"] = "2.4.0"
                var capabilities: [String: Any] = Dictionary(uniqueKeysWithValues: flags.map { ($0, true) })
                capabilities[flag] = invalid
                changed["capabilities"] = capabilities
                let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": changed])
                XCTAssertNil(KimiDesktopServerMetadata.parse(data, expected: try registration(version: "2.4.0"),
                    installedVersion: "1.2.1"), flag)
            }
        }
        var changed = body()
        changed["server_version"] = "2.4.0"
        changed["capabilities"] = Dictionary(uniqueKeysWithValues: flags.map { ($0, true) })
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": changed])
        XCTAssertNil(KimiDesktopServerMetadata.parse(data, expected: try registration(), installedVersion: "1.2.1"))
        XCTAssertNotNil(KimiDesktopServerMetadata.parse(data, expected: try registration(version: nil), installedVersion: "1.2.1"))
    }
    func testOfficialAPIIdentityIsIndependentOfRegistryIdentity() throws {
        var changed = body()
        let apiID = "01" + String(repeating: "B", count: 24)
        changed["server_id"] = apiID
        let metadata = try XCTUnwrap(parse(changed))
        XCTAssertEqual(metadata.serverID, apiID)
    }

    func testTimestampMustMatchOfficialDateShapeAndBoundedInstanceStartup() throws {
        for time in ["2027-01-15T07:59:59.999Z", "2027-01-15T08:01:00.001Z",
                     "2027-01-15T08:00:00Z", "2027-02-30T08:00:00.250Z", "not a date"] {
            var changed = body(); changed["started_at"] = time
            XCTAssertNil(try parse(changed), time)
        }
        for offset in [0, 1, 59_999, 60_000] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var changed = body()
            changed["started_at"] = formatter.string(from: Date(timeIntervalSince1970: Double(started + Int64(offset)) / 1000))
            XCTAssertNotNil(try parse(changed), "Legitimate instance startup delay")
        }
    }

    func testHTTPBusinessFailureAndBooleanCodeCannotBecomeSuccess() throws {
        for code: Any in [false, true, "0", 0.5, 401, 500] {
            XCTAssertNil(try parse(body(), code: code))
        }
    }
    func testAnotherInstanceRestartOrUninspectedVersionFailsBinding() throws {
        for (key, value): (String, Any) in [("server_id", "not-an-api-id"),
                                          ("started_at", started + 1), ("server_version", "2.4.0"),
                                          ("backend", "v1")] {
            var changed = body(); changed[key] = value
            XCTAssertNil(try parse(changed))
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": body()])
        XCTAssertNil(KimiDesktopServerMetadata.parse(data, expected: try registration(version: "2.3.3"), installedVersion: "1.1.3"))
        XCTAssertNotNil(KimiDesktopServerMetadata.parse(data, expected: try registration(version: nil), installedVersion: "1.1.3"))
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
        XCTAssertNil(KimiDesktopServerMetadata.parse(Data("not json".utf8), expected: expected, installedVersion: "1.1.3"))
        XCTAssertNil(KimiDesktopServerMetadata.parse(Data(repeating: 32, count: 65_537), expected: expected, installedVersion: "1.1.3"))
        var changed = body(); changed["started_at"] = true
        XCTAssertNil(try parse(changed))
    }
}
