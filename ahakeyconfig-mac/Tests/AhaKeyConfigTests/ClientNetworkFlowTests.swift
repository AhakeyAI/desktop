import XCTest
@testable import AhaKeyConfig
import AhaKeyConfigShared

private final class ClientStubProtocol: URLProtocol {
    static var handle: (URLRequest) -> (Int, String) = { _ in (500, "") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, body) = Self.handle(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ClientNetworkFlowTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClientStubProtocol.self]
        return URLSession(configuration: config)
    }
    private let release = #"{"tag_name":"v0.2.4","html_url":"https://github.com/AhakeyAI/desktop/releases/tag/v0.2.4","assets":[]}"#

    func test403FallsBackToPublicPageWithDigestAndRemembersAPILimit() async throws {
        var apiCalls = 0
        ClientStubProtocol.handle = { request in
            if request.url!.host == "api.github.com" { apiCalls += 1; return (403, "rate limit") }
            if request.url!.path.hasSuffix("/latest") { return (200, #"<include-fragment src="/AhakeyAI/desktop/releases/expanded_assets/v0.2.4">"#) }
            return (200, "<li><a href=\"/AhakeyAI/desktop/releases/download/v0.2.4/AhaKey-Studio-macOS.dmg\">DMG</a><span>sha256:\(String(repeating: "a", count: 64))</span></li>")
        }
        let manager = AppUpdateManager(session: session(), installedVersion: "0.2.3")
        await manager.checkForUpdates(manual: false)
        XCTAssertEqual(manager.availableRelease?.tagName, "v0.2.4")
        XCTAssertNotNil(manager.availableRelease?.macDMG)
        XCTAssertTrue(manager.isVisible)
        manager.isVisible = false
        await manager.checkForUpdates(manual: true)
        XCTAssertEqual(apiCalls, 1)
        XCTAssertTrue(manager.isVisible)
    }

    func testAutomaticCheckDoesNotDownloadOrShowNoUpdatePopup() async {
        var requests = 0
        ClientStubProtocol.handle = { _ in requests += 1; return (200, self.release) }
        let manager = AppUpdateManager(session: session(), installedVersion: "0.2.4")
        await manager.checkForUpdates(manual: false)
        XCTAssertFalse(manager.isVisible)
        XCTAssertFalse(manager.isDownloading)
        XCTAssertEqual(requests, 1)
        await manager.checkForUpdates(manual: true)
        XCTAssertTrue(manager.isVisible)
        XCTAssertNil(manager.availableRelease)
    }

    func testDownloadIsVerifiedAndReadyWithoutOpeningInstaller() async throws {
        ClientStubProtocol.handle = { _ in (200, "abc") }
        let json = #"{"tag_name":"v0.2.4","html_url":"https://github.com/AhakeyAI/desktop/releases/tag/v0.2.4","assets":[{"name":"AhaKey-Studio-macOS.dmg","browser_download_url":"https://github.com/AhakeyAI/desktop/releases/download/v0.2.4/AhaKey-Studio-macOS.dmg","digest":"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}]}"#
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
        let manager = AppUpdateManager(session: session(), installedVersion: "0.2.3")
        await manager.download(release)
        let file = try XCTUnwrap(manager.downloadedFile, manager.statusMessage ?? "")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try Data(contentsOf: file), Data("abc".utf8))
        XCTAssertFalse(manager.isDownloading)
        XCTAssertTrue(manager.isVisible)
        let bad = try JSONDecoder().decode(AppRelease.self, from: Data(json.replacingOccurrences(of: "ba7816bf", with: "00000000").utf8))
        let failed = AppUpdateManager(session: session(), installedVersion: "0.2.3")
        await failed.download(bad)
        XCTAssertNil(failed.downloadedFile)
        XCTAssertFalse(failed.isDownloading)
    }

    func testDownloadProgressReportsBytesTotalAndSpeed() {
        var bytes: Int64 = 0, total: Int64 = 0, speed: Double = 0
        let delegate = UpdateDownloadProgress { bytes = $0; total = $1; speed = $2 }
        let transport = session(), task = session().downloadTask(with: URL(string: "https://github.com/test")!)
        delegate.urlSession(transport, downloadTask: task, didWriteData: 4096, totalBytesWritten: 4096, totalBytesExpectedToWrite: 4096)
        XCTAssertEqual(bytes, 4096)
        XCTAssertEqual(total, 4096)
        XCTAssertGreaterThan(speed, 0)
        task.cancel()
    }

    private func optimizer(token: String = "test-token", callback: @escaping (String?) -> Void) throws -> (AhaTypeTextOptimizer, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("config.json")
        try JSONSerialization.data(withJSONObject: ["access_token": token, "typeless_enabled": true, "token_valid_until": "2099-01-01T00:00:00Z"]).write(to: file)
        return (AhaTypeTextOptimizer(configURL: file, session: session(), onLoginRequired: callback), folder)
    }

    func testAhaType401ClearsSessionRequestsLoginAndPreservesTranscription() async throws {
        ClientStubProtocol.handle = { _ in (401, "not JSON") }
        var redirects = 0
        let (optimizer, folder) = try optimizer { _ in redirects += 1 }
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "原始转写"
        let output = await optimizer.processIfEnabled(original)
        XCTAssertEqual(output, original)
        XCTAssertEqual(redirects, 1)
        XCTAssertTrue(optimizer.requiresLogin)
        XCTAssertFalse(optimizer.hasConfiguredCloudToken)
        XCTAssertTrue(optimizer.isEnabled)
    }

    func testLogicalTokenFailureRedirectsButQuota403DoesNot() async throws {
        for (code, body, shouldRedirect) in [(200, #"{"code":500,"msg":"Token 无效"}"#, true), (403, #"{"code":403,"message":"quota exceeded"}"#, false)] {
            ClientStubProtocol.handle = { _ in (code, body) }
            var redirects = 0
            let (optimizer, folder) = try optimizer { _ in redirects += 1 }
            defer { try? FileManager.default.removeItem(at: folder) }
            _ = await optimizer.processIfEnabled("speech")
            XCTAssertEqual(redirects, shouldRedirect ? 1 : 0)
            XCTAssertEqual(optimizer.hasConfiguredCloudToken, !shouldRedirect)
        }
    }

    func testMissingTokenRedirectsWithoutNetworkRequest() async throws {
        ClientStubProtocol.handle = { _ in XCTFail("must not send unauthenticated speech"); return (500, "") }
        var redirects = 0
        let (optimizer, folder) = try optimizer(token: "") { _ in redirects += 1 }
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = await optimizer.processIfEnabled("speech")
        XCTAssertEqual(redirects, 1)
    }

    func testRecordingDecisionIsNotReplacedByLaterGlobalToggle() async throws {
        let (optimizer, folder) = try optimizer { _ in XCTFail("valid token") }
        defer { try? FileManager.default.removeItem(at: folder) }
        var requests = 0
        ClientStubProtocol.handle = { _ in
            requests += 1
            return (200, #"{"code":0,"data":{"text":"processed"}}"#)
        }
        optimizer.setEnabled(false)
        let capturedEnabled = await optimizer.processIfEnabled("speech", enabledForRecording: true)
        XCTAssertEqual(capturedEnabled, "processed")
        XCTAssertEqual(requests, 1)
        optimizer.setEnabled(true)
        let capturedDisabled = await optimizer.processIfEnabled("speech", enabledForRecording: false)
        XCTAssertEqual(capturedDisabled, "speech")
        XCTAssertEqual(requests, 1)
    }

    func testCapturedRecordingDecisionStillRequiresCurrentAuthentication() async throws {
        var redirects = 0
        let (optimizer, folder) = try optimizer(token: "") { _ in redirects += 1 }
        defer { try? FileManager.default.removeItem(at: folder) }
        optimizer.setEnabled(false)
        ClientStubProtocol.handle = { _ in XCTFail("missing credentials must not send speech"); return (500, "") }
        let text = await optimizer.processIfEnabled("speech", enabledForRecording: true)
        XCTAssertEqual(text, "speech")
        XCTAssertEqual(redirects, 1)
    }

    func testExpiredTokenDoesNotSendSpeechAndLateFailureCannotClearNewToken() async throws {
        var redirects = 0
        let (optimizer, folder) = try optimizer { _ in redirects += 1 }
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.json")
        var payload = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        payload["token_valid_until"] = "2000-01-01T00:00:00Z"
        try JSONSerialization.data(withJSONObject: payload).write(to: file)
        ClientStubProtocol.handle = { _ in XCTFail("expired token should not reach network"); return (500, "") }
        _ = await optimizer.processIfEnabled("speech")
        XCTAssertEqual(redirects, 1)
        payload["access_token"] = "old-token"
        payload["token_valid_until"] = "2099-01-01T00:00:00Z"
        try JSONSerialization.data(withJSONObject: payload).write(to: file)
        ClientStubProtocol.handle = { _ in
            var fresh = (try! JSONSerialization.jsonObject(with: Data(contentsOf: file))) as! [String: Any]
            fresh["access_token"] = "new-token"
            try! JSONSerialization.data(withJSONObject: fresh).write(to: file)
            return (401, "")
        }
        _ = await optimizer.processIfEnabled("speech")
        XCTAssertEqual(redirects, 1)
        let latest = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(latest["access_token"] as? String, "new-token")
    }

    func testQuietProfile401ReturnsAccountToLoginAndStaleTokenCannotLogOutNewAccount() async throws {
        ClientStubProtocol.handle = { _ in (401, "") }
        let (optimizer, folder) = try optimizer { _ in }
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "AhaKey.ClientNetworkFlowTests.\(UUID())", tokenKey = "lab.jawa.ahakeyconfig.cloud.accessToken"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("new-token", forKey: tokenKey)
        let account = CloudAccountManager(defaults: defaults, session: session(), optimizer: optimizer)
        account.requireLogin(ifTokenMatches: "old-token")
        XCTAssertTrue(account.isLoggedIn)
        account.refreshProfile(showAlertOnFailure: false)
        for _ in 0..<100 where account.loginRequestID == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(account.isLoggedIn)
        XCTAssertNotNil(account.loginRequestID)
        XCTAssertNil(defaults.string(forKey: tokenKey))
        XCTAssertNil(account.alertMessage)
    }
}
