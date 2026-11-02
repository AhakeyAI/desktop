import XCTest
@testable import AhaKeyConfigShared

final class KimiDesktopVerifiedExchangeTests: XCTestCase {
    private let registryID = "01" + String(repeating: "A", count: 24)
    private let apiID = "01" + String(repeating: "B", count: 24)
    private func registration(version: String = "2.3.2") throws -> KimiDesktopInstanceDiscovery.Registration {
        let value: [String: Any] = ["server_id": registryID, "pid": 1234, "host": "127.0.0.1", "port": 23456,
            "started_at": 1_800_000_000_000 as Int64, "heartbeat_at": 1_800_000_001_000 as Int64, "host_version": version]
        return try XCTUnwrap(KimiDesktopInstanceDiscovery.Registration.parse(JSONSerialization.data(withJSONObject: value),
            filename: registryID + ".json", nowMilliseconds: 1_800_000_001_000))
    }
    private func metadata(_ id: String, version: String = "2.3.2") throws -> Data {
        let flags = ["websocket", "file_upload", "fs_query", "mcp", "tasks"] + (version == "2.3.2" ? ["terminal"] : [])
        return try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["server_id": id, "server_version": version,
            "started_at": "2027-01-15T08:00:00.250Z", "dangerous_bypass_auth": false, "backend": "v2",
            "capabilities": Dictionary(uniqueKeysWithValues: flags.map { ($0, true) })]])
    }
    func testDifferentRegistryAndAPIIdentitiesStillBracketRealOperation() async throws {
        let meta = try metadata(apiID), expected = try registration(), result = Data("fixture status".utf8)
        var paths: [String] = []
        let actual = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, installedVersion: "1.1.3", method: "GET", path: "/api/v1/sessions/session/status") { method, path, _, body in
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
            _ = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, installedVersion: "1.1.3", method: "POST", path: "/api/v1/sessions/session/profile") { _, path, _, _ in
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
            _ = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: registration(), installedVersion: "1.1.3", method: "POST", path: "/api/v1/sessions/session/profile") { _, _, _, _ in
                requests += 1; return Data("{}".utf8)
            }
            XCTFail("Invalid metadata")
        } catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .instanceChanged) }
        XCTAssertEqual(requests, 1)
    }
    func test240ProfileWriteIsBracketedAndBodyIsPreserved() async throws {
        let expected = try registration(version: "2.4.0"), meta = try metadata(apiID, version: "2.4.0")
        let body = Data(#"{"agent_config":{"permission_mode":"auto"}}"#.utf8)
        let ack = Data(#"{"code":0,"data":{"id":"session"}}"#.utf8)
        var paths: [String] = []
        let result = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, installedVersion: "1.2.1",
            method: "POST", path: "/api/v1/sessions/session/profile", body: body) { method, path, query, requestBody in
                paths.append(path)
                XCTAssertTrue(query.isEmpty)
                if path.hasSuffix("/meta") { XCTAssertEqual(method, "GET"); XCTAssertNil(requestBody); return meta }
                XCTAssertEqual(method, "POST"); XCTAssertEqual(requestBody, body)
                return ack
            }
        XCTAssertEqual(result, ack)
        XCTAssertEqual(paths, ["/api/v1/meta", "/api/v1/sessions/session/profile", "/api/v1/meta"])
    }
    func test240CannotSendPermissionWriteFromMismatchedDesktopVersion() async throws {
        let expected = try registration(version: "2.4.0"), meta = try metadata(apiID, version: "2.4.0")
        var paths: [String] = []
        do {
            _ = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, installedVersion: "1.1.3",
                method: "POST", path: "/api/v1/sessions/session/profile") { _, path, _, _ in
                    paths.append(path); return meta
                }
            XCTFail("Mismatched signed bundle version must fail before any session request")
        } catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .instanceChanged) }
        XCTAssertEqual(paths, ["/api/v1/meta"])
    }
    func test240VersionChangeAfterWriteDoesNotRetryPossiblyAppliedPermission() async throws {
        let expected = try registration(version: "2.4.0")
        let before = try metadata(apiID, version: "2.4.0"), changed = try metadata(apiID)
        var metaReads = 0, writes = 0
        do {
            _ = try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, installedVersion: "1.2.1",
                method: "POST", path: "/api/v1/sessions/session/profile") { _, path, _, _ in
                    if path.hasSuffix("/meta") { metaReads += 1; return metaReads == 1 ? before : changed }
                    writes += 1; return Data(#"{"code":0,"data":{"id":"session"}}"#.utf8)
                }
            XCTFail("Changed metadata after POST cannot publish success")
        } catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .instanceChanged) }
        XCTAssertEqual(metaReads, 2)
        XCTAssertEqual(writes, 1)
    }
    private actor Server240 {
        let meta: Data
        var mode = KimiDesktopPermissionBridge.Mode.manual
        var paths: [String] = []
        var writes = 0
        init(meta: Data) { self.meta = meta }
        func request(_ method: String, _ path: String, _ query: [URLQueryItem], _ body: Data?) throws -> Data {
            paths.append(method + " " + path)
            if path == "/api/v1/meta" { return meta }
            let result: [String: Any]
            if path == "/api/v2/sessions" {
                XCTAssertEqual(method, "GET"); XCTAssertNil(body)
                XCTAssertEqual(query, [URLQueryItem(name: "view", value: "flat"), URLQueryItem(name: "page_size", value: "32")])
                result = ["items": [
                    ["id": "loaded", "meta": ["title": "Static fixture", "archived": false], "activity": ["model": "fixture-model"]],
                    ["id": "cold", "meta": ["title": "Cold fixture", "archived": false], "activity": ["model": NSNull()]]
                ], "has_more": false, "next_page_token": NSNull()]
            } else if method == "GET", path == "/api/v1/sessions/loaded/status" {
                XCTAssertNil(body); result = ["permission": mode.rawValue]
            } else if method == "POST", path == "/api/v1/sessions/loaded/profile" {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
                let config = try XCTUnwrap(object["agent_config"] as? [String: String])
                XCTAssertEqual(Set(object.keys), ["agent_config"])
                XCTAssertEqual(Set(config.keys), ["permission_mode"])
                mode = try XCTUnwrap(KimiDesktopPermissionBridge.Mode(rawValue: XCTUnwrap(config["permission_mode"])))
                writes += 1; result = ["id": "loaded"]
            } else { throw KimiDesktopPermissionBridge.Failure.invalidTarget }
            return try JSONSerialization.data(withJSONObject: ["code": 0, "data": result])
        }
    }
    func test240SessionDiscoveryAndPermissionRoundTripUseExistingAuthorizedBridge() async throws {
        let expected = try registration(version: "2.4.0"), server = Server240(meta: try metadata(apiID, version: "2.4.0"))
        let bridge = KimiDesktopPermissionBridge(authorization: { id, _ in id == nil || id == "loaded" },
            exchange: { _, _, method, path, query, body in
                try await KimiDesktopPermissionHTTP.verifiedExchange(expected: expected, installedVersion: "1.2.1",
                    method: method, path: path, query: query, body: body) { method, path, query, body in
                        try await server.request(method, path, query, body)
                    }
            })
        let page = try await bridge.loadedSessions()
        XCTAssertEqual(page.loadedSessions.map(\.id), ["loaded"])
        let beforeUnauthorized = await server.paths
        do { _ = try await bridge.readPermission(sessionID: "cold"); XCTFail("No grant for cold session") }
        catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .unauthorized) }
        let afterUnauthorized = await server.paths
        XCTAssertEqual(beforeUnauthorized, afterUnauthorized)
        let automatic = try await bridge.setPermission(sessionID: "loaded", expecting: .manual, to: .auto)
        XCTAssertEqual(automatic.mode, .auto); XCTAssertTrue(automatic.attemptedWrite)
        let restored = try await bridge.setPermission(sessionID: "loaded", expecting: .auto, to: .manual)
        XCTAssertEqual(restored.mode, .manual); XCTAssertTrue(restored.attemptedWrite)
        let paths = await server.paths, writes = await server.writes
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(paths.filter { $0.hasSuffix("/meta") }.count, 14)
        XCTAssertEqual(paths.filter { !$0.hasSuffix("/meta") }, ["GET /api/v2/sessions"] + Array(repeating: [
            "GET /api/v1/sessions/loaded/status", "POST /api/v1/sessions/loaded/profile", "GET /api/v1/sessions/loaded/status"
        ], count: 2).flatMap { $0 })
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
