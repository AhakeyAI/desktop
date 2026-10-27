import XCTest
@testable import AhaKeyConfigShared

final class KimiDesktopVerifiedExchangeTests: XCTestCase {
    private let registryID = "01" + String(repeating: "A", count: 24)
    private let apiID = "01" + String(repeating: "B", count: 24)
    private func registration() throws -> KimiDesktopInstanceDiscovery.Registration {
        let value: [String: Any] = ["server_id": registryID, "pid": 1234, "host": "127.0.0.1", "port": 23456,
            "started_at": 1_800_000_000_000 as Int64, "heartbeat_at": 1_800_000_001_000 as Int64, "host_version": "2.3.2"]
        return try XCTUnwrap(KimiDesktopInstanceDiscovery.Registration.parse(JSONSerialization.data(withJSONObject: value),
            filename: registryID + ".json", nowMilliseconds: 1_800_000_001_000))
    }
    private func metadata(_ id: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["server_id": id, "server_version": "2.3.2",
            "started_at": "2027-01-15T08:00:00.250Z", "dangerous_bypass_auth": false, "backend": "v2",
            "capabilities": Dictionary(uniqueKeysWithValues: ["websocket", "file_upload", "fs_query", "mcp", "tasks", "terminal"].map { ($0, true) })]])
    }
    func testDifferentRegistryAndAPIIdentitiesStillBracketRealOperation() async throws {
        let meta = try metadata(apiID), expected = try registration(), result = Data("fixture status".utf8)
        var paths: [String] = []
        let actual = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, method: "GET", path: "/api/v1/sessions/session/status") { method, path, _, body in
            XCTAssertEqual(method, "GET"); XCTAssertNil(body); paths.append(path)
            return path.hasSuffix("/meta") ? meta : result
        }
        XCTAssertEqual(actual, result)
        XCTAssertEqual(paths, ["/api/v1/meta", "/api/v1/sessions/session/status", "/api/v1/meta"])
    }
    func testChangedAPIApplicationCannotPublishSuccess() async throws {
        let before = try metadata(apiID), after = try metadata("01" + String(repeating: "C", count: 24)), expected = try registration()
        var metaReads = 0, operations = 0
        do {
            _ = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, method: "POST", path: "/api/v1/sessions/session/profile") { _, path, _, _ in
                if path.hasSuffix("/meta") { metaReads += 1; return metaReads == 1 ? before : after }
                operations += 1; return Data("unconfirmed ACK".utf8)
            }
            XCTFail("Changed API owner")
        } catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .instanceChanged) }
        XCTAssertEqual(operations, 1, "Never retry a possibly applied POST")
    }
    func testInvalidInitialMetadataSendsNoPermissionOperation() async throws {
        var requests = 0
        do {
            _ = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: registration(), method: "POST", path: "/api/v1/sessions/session/profile") { _, _, _, _ in
                requests += 1; return Data("{}".utf8)
            }
            XCTFail("Invalid metadata")
        } catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .instanceChanged) }
        XCTAssertEqual(requests, 1)
    }
    func testProductionWritePolicyPermitsOriginalBaselineDuringTerminationOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = KimiDesktopLeverState(directory: root)
        let target = try KimiDesktopLeverState.Target(home: "/tmp/kimi-home", sessionID: "session")
        try state.authorize(target, title: "Fixture")
        let lease = try state.prepare(target, baseline: .yolo, intended: .auto)
        XCTAssertFalse(KimiDesktopLeverCoordinator.Dependencies.permitsWrite(lease: lease, desired: .yolo,
            granted: true, controlEnabled: true, authority: .automatic, managing: false))
        XCTAssertTrue(KimiDesktopLeverCoordinator.Dependencies.permitsWrite(lease: lease, desired: .yolo,
            granted: true, controlEnabled: true, authority: .unmanaged, managing: false))
        XCTAssertFalse(KimiDesktopLeverCoordinator.Dependencies.permitsWrite(lease: lease, desired: .auto,
            granted: true, controlEnabled: true, authority: .unmanaged, managing: true))
        XCTAssertFalse(KimiDesktopLeverCoordinator.Dependencies.permitsWrite(lease: lease, desired: .manual,
            granted: true, controlEnabled: true, authority: .unmanaged, managing: false))
    }
}
