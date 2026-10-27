import XCTest
@testable import AhaKeyConfigShared

final class KimiDesktopPermissionBridgeTests: XCTestCase {
    private let id = "01KIMI_AUTHORIZED_SESSION"
    private func reply(_ body: [String: Any], code: Any = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": code, "data": body])
    }
    private actor Server {
        var permission: KimiDesktopPermissionBridge.Mode = .yolo
        var paths: [String] = []
        var lost = false, ignore = false, wrong = false
        func configure(lost: Bool = false, ignore: Bool = false, wrong: Bool = false) { self.lost = lost; self.ignore = ignore; self.wrong = wrong }
        func request(id: String?, mode: KimiDesktopPermissionBridge.Mode?, method: String, path: String, body: Data?) throws -> Data {
            paths.append(method + " " + path)
            if method == "GET" { return try encode(["permission": permission.rawValue]) }
            let object = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as! [String: Any]
            let config = try XCTUnwrap(object["agent_config"] as? [String: String])
            XCTAssertEqual(object.count, 1); XCTAssertEqual(config.count, 1)
            let next = try XCTUnwrap(KimiDesktopPermissionBridge.Mode(rawValue: XCTUnwrap(config["permission_mode"])))
            XCTAssertEqual(next, mode)
            if !ignore { permission = next }
            if lost { throw KimiDesktopPermissionBridge.Failure.unavailable }
            return try encode(["id": wrong ? "OTHER" : XCTUnwrap(id)])
        }
        func encode(_ data: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: ["code": 0, "data": data]) }
    }
    private func bridge(_ server: Server) -> KimiDesktopPermissionBridge {
        .init(authorization: { id, _ in id == "01KIMI_AUTHORIZED_SESSION" }, exchange: { id, mode, method, path, _, body in
            try await server.request(id: id, mode: mode, method: method, path: path, body: body)
        })
    }
    func testUnauthorizedOrInvalidTargetSendsNothing() async {
        let server = Server(), api = bridge(server)
        for id in ["unapproved", "../other", "a/b", "a?token=x", "a\n", ""] {
            do { _ = try await api.readPermission(sessionID: id); XCTFail("Unapproved target") } catch {}
        }
        let paths = await server.paths; XCTAssertTrue(paths.isEmpty)
    }
    func testOnlyPermissionIsWrittenAndReadBackIndependently() async throws {
        let server = Server()
        let result = try await bridge(server).setPermission(sessionID: id, expecting: .yolo, to: .auto)
        XCTAssertEqual(result.mode, .auto); XCTAssertTrue(result.attemptedWrite)
        let paths = await server.paths
        XCTAssertEqual(paths, ["GET /api/v1/sessions/\(id)/status", "POST /api/v1/sessions/\(id)/profile", "GET /api/v1/sessions/\(id)/status"])
    }
    func testExternalChangeStopsBeforePost() async {
        let server = Server()
        do { _ = try await bridge(server).setPermission(sessionID: id, expecting: .manual, to: .auto); XCTFail("Conflict") }
        catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .conflict(.yolo)) }
        let paths = await server.paths; XCTAssertEqual(paths.count, 1)
    }
    func testAlreadyDesiredDoesNotPost() async throws {
        let server = Server()
        let result = try await bridge(server).setPermission(sessionID: id, expecting: .yolo, to: .yolo)
        XCTAssertFalse(result.attemptedWrite)
        let paths = await server.paths; XCTAssertEqual(paths.count, 1)
    }
    func testLostReplyReadsBackWithoutRetryingPost() async throws {
        let server = Server(); await server.configure(lost: true)
        let result = try await bridge(server).setPermission(sessionID: id, expecting: .yolo, to: .auto)
        XCTAssertEqual(result.mode, .auto)
        let paths = await server.paths; XCTAssertEqual(paths.filter { $0.hasPrefix("POST") }.count, 1)
    }
    func testAckWithoutApplicationCannotProveSuccess() async {
        let server = Server(); await server.configure(ignore: true)
        do { _ = try await bridge(server).setPermission(sessionID: id, expecting: .yolo, to: .auto); XCTFail("No proof") }
        catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .notApplied) }
    }
    func testWrongSessionAckIsRejected() async {
        let server = Server(); await server.configure(wrong: true)
        do { _ = try await bridge(server).setPermission(sessionID: id, expecting: .yolo, to: .auto); XCTFail("Wrong target") }
        catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .invalidResponse) }
    }
    func testBooleanErrorCodeAndUnknownModesRejected() async throws {
        for (code, mode): (Any, String) in [(false, "manual"), (true, "manual"), (401, "auto"), (0, "unknown")] {
            let data = try reply(["permission": mode], code: code)
            let api = KimiDesktopPermissionBridge(authorization: { _, _ in true }, exchange: { _, _, _, _, _, _ in data })
            do { _ = try await api.readPermission(sessionID: id); XCTFail("Invalid response") } catch {}
        }
    }
    func testOnlyLoadedNonArchivedSessionsAreOffered() async throws {
        let data = try reply(["items": [
            ["id": id, "meta": ["title": "Code project", "archived": false], "activity": ["model": "model"]],
            ["id": "cold", "meta": ["title": "Cold", "archived": false], "activity": ["model": NSNull()]],
            ["id": "archive", "meta": ["title": "Archived", "archived": true], "activity": ["model": "model"]]
        ], "has_more": false, "next_page_token": NSNull()])
        let api = KimiDesktopPermissionBridge(authorization: { id, _ in id == nil }, exchange: { id, mode, method, path, query, body in
            XCTAssertNil(id); XCTAssertNil(mode); XCTAssertEqual(method, "GET"); XCTAssertNil(body)
            XCTAssertEqual(path, "/api/v2/sessions"); XCTAssertEqual(query.first { $0.name == "page_size" }?.value, "32")
            return data
        })
        let page = try await api.loadedSessions()
        XCTAssertEqual(page.loadedSessions.map(\.id), [id]); XCTAssertNil(page.nextPageToken)
    }
    func testConsentRevokedDuringReadDiscardsResult() async throws {
        actor Consent { var enabled = true; func revoke() { enabled = false } }
        let consent = Consent(), data = try reply(["permission": "auto"])
        let api = KimiDesktopPermissionBridge(authorization: { _, _ in await consent.enabled }, exchange: { _, _, _, _, _, _ in
            await consent.revoke(); return data
        })
        do { _ = try await api.readPermission(sessionID: id); XCTFail("Revoked") }
        catch { XCTAssertEqual(error as? KimiDesktopPermissionBridge.Failure, .unauthorized) }
    }
}
