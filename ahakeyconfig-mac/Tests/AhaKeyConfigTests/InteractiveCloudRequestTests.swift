import Foundation
import XCTest
@testable import AhaKeyConfig

private final class LatencyProtocol: URLProtocol {
    final class Scenario {
        let delay: TimeInterval?
        let started: XCTestExpectation?
        let stopped: XCTestExpectation?
        let incompleteBody: Bool
        init(delay: TimeInterval? = nil, started: XCTestExpectation? = nil, stopped: XCTestExpectation? = nil, incompleteBody: Bool = false) {
            self.delay = delay; self.started = started; self.stopped = stopped
            self.incompleteBody = incompleteBody
        }
    }
    private static let registryLock = NSLock()
    private static var scenarios: [String: Scenario] = [:]
    private let lock = NSLock()
    private var work: DispatchWorkItem?
    private var stopped = false
    private var scenario: Scenario?

    static func register(_ scenario: Scenario) -> String {
        let key = UUID().uuidString
        registryLock.lock(); scenarios[key] = scenario; registryLock.unlock()
        return key
    }
    static func remove(_ key: String) { registryLock.lock(); scenarios[key] = nil; registryLock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.registryLock.lock()
        let scenario = request.value(forHTTPHeaderField: "X-AhaKey-Test").flatMap { Self.scenarios[$0] }
        Self.registryLock.unlock()
        guard let scenario else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        lock.lock(); self.scenario = scenario; let stopped = stopped; lock.unlock()
        if stopped { return }
        scenario.started?.fulfill()
        if scenario.incompleteBody {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("partial body".utf8))
            return
        }
        guard let delay = scenario.delay else { return } // server never responds
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock(); let stopped = self.stopped; self.lock.unlock()
            guard !stopped else { return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(#"{"code":0,"data":{"text":"processed"}}"#.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        lock.lock(); self.work = work; let cancelled = self.stopped; lock.unlock()
        if cancelled { work.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }
    override func stopLoading() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let work = work, scenario = scenario
        lock.unlock()
        work?.cancel(); scenario?.stopped?.fulfill()
    }
}

final class InteractiveCloudRequestTests: XCTestCase {
    private func fixture(_ scenario: LatencyProtocol.Scenario) -> (URLSession, URLRequest) {
        let key = LatencyProtocol.register(scenario)
        addTeardownBlock { LatencyProtocol.remove(key) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LatencyProtocol.self]
        config.httpAdditionalHeaders = ["X-AhaKey-Test": key]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        return (session, URLRequest(url: URL(string: "https://latency.invalid/process")!))
    }

    func testAbsoluteDeadlineReleasesSilentRequestAndCancelsTransport() async {
        let stopped = expectation(description: "transport cancelled")
        let (session, request) = fixture(.init(stopped: stopped))
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await InteractiveCloudRequest.data(for: request, session: session, budget: 0.05)
            XCTFail("silent request completed")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testCallerCancellationSettlesWithoutWaitingForCloud() async {
        let started = expectation(description: "request started"), stopped = expectation(description: "transport stopped")
        let (session, request) = fixture(.init(started: started, stopped: stopped))
        let task = Task { try await InteractiveCloudRequest.data(for: request, session: session, budget: 8) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled request returned") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testAbsoluteDeadlineIncludesIncompleteResponseBody() async {
        let stopped = expectation(description: "partial response cancelled")
        let (session, request) = fixture(.init(stopped: stopped, incompleteBody: true))
        do {
            _ = try await InteractiveCloudRequest.data(for: request, session: session, budget: 0.05)
            XCTFail("incomplete response must time out")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testFastCloudResponseIsPreserved() async throws {
        let (session, request) = fixture(.init(delay: 0))
        let (data, response) = try await InteractiveCloudRequest.data(for: request, session: session, budget: 1)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("processed"))
    }

    func testAlreadyCancelledCallerDoesNotBeginNetworkRequest() async {
        let started = expectation(description: "no network after cancellation")
        started.isInverted = true
        let (session, request) = fixture(.init(started: started))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await InteractiveCloudRequest.data(for: request, session: session, budget: 8)
        }
        do { _ = try await task.value; XCTFail("cancelled request returned") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [started], timeout: 0.05)
    }

    @MainActor
    func testCloudDeadlinePreservesOriginalTextAndReportsFallbackOnce() async throws {
        let (session, _) = fixture(.init())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("account.json")
        try JSONSerialization.data(withJSONObject: ["access_token": "fixture-token", "typeless_enabled": true,
            "token_valid_until": "2099-01-01T00:00:00Z"]).write(to: config)
        let optimizer = AhaTypeTextOptimizer(configURL: config, session: session, onLoginRequired: { _ in XCTFail("valid token") }, processingTimeout: 0.05)
        var notices = 0
        let output = await optimizer.processIfEnabled("确认确认，完整原文", onTimeout: { notices += 1 })
        XCTAssertEqual(output, "确认确认，完整原文")
        XCTAssertEqual(notices, 1)
        XCTAssertTrue(optimizer.hasConfiguredCloudToken)
        XCTAssertTrue(optimizer.statusMessage.contains("超时"))
    }

    @MainActor
    func testOldAccountTimeoutDoesNotOverrideNewLogin() async throws {
        let started = expectation(description: "old request started")
        let (session, _) = fixture(.init(started: started))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("account.json")
        func save(_ token: String) throws {
            try JSONSerialization.data(withJSONObject: ["access_token": token, "typeless_enabled": true,
                "token_valid_until": "2099-01-01T00:00:00Z"]).write(to: config)
        }
        try save("old-fixture-token")
        let optimizer = AhaTypeTextOptimizer(configURL: config, session: session,
            onLoginRequired: { _ in XCTFail("new account remains valid") }, processingTimeout: 0.2)
        let completion = Task { await optimizer.processIfEnabled("original", onTimeout: { XCTFail("obsolete account must not update UI") }) }
        await fulfillment(of: [started], timeout: 1)
        try save("new-fixture-token")
        optimizer.refreshFromDisk()
        let currentStatus = optimizer.statusMessage
        let output = await completion.value
        XCTAssertEqual(output, "original")
        XCTAssertEqual(optimizer.statusMessage, currentStatus)
        XCTAssertTrue(optimizer.hasConfiguredCloudToken)
    }
}
