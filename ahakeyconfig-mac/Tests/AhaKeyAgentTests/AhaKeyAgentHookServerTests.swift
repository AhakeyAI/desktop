import XCTest
import Darwin
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

/// HIL-RUNTIME-1-HOOK-SERVER：验证生产 Agent 实例化并监听 hook.sock，
/// 且 handler 正确映射拨杆状态到 approval/lever 响应。
/// 所有测试使用隔离的临时 socket 路径，不触碰生产 `~/Library/Application Support/AhaKeyConfig/private/hook.sock`。
final class AhaKeyAgentHookServerTests: XCTestCase {
    private var agent: AhaKeyAgent!
    private var testHookURL: URL!

    override func setUp() {
        super.setUp()
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-agent-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        testHookURL = root.appendingPathComponent("private", isDirectory: true)
            .appendingPathComponent("hook.sock")
        agent = AhaKeyAgent(
            socketPath: "/tmp/ahk-agent-test-\(UUID().uuidString.prefix(8)).sock",
            hookSocketURL: testHookURL
        )
    }

    override func tearDown() {
        agent?.shutdown()
        // 仅清理临时测试目录，不触碰生产路径
        if let url = testHookURL {
            let parent = url.deletingLastPathComponent().deletingLastPathComponent()
            try? FileManager.default.removeItem(at: parent)
        }
        super.tearDown()
    }

    // MARK: - 生产接线：Server 启动与权限

    func testHookServerStartsAndCreatesSocketWithCorrectPermissions() throws {
        try agent.startHookServer()

        var status = stat()
        XCTAssertEqual(lstat(testHookURL.path, &status), 0)
        XCTAssertEqual(status.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(status.st_mode & 0o777, 0o600)
        XCTAssertEqual(status.st_uid, getuid())

        let parent = testHookURL.deletingLastPathComponent().path
        var dirStatus = stat()
        XCTAssertEqual(lstat(parent, &dirStatus), 0)
        XCTAssertEqual(dirStatus.st_mode & S_IFMT, S_IFDIR)
        XCTAssertEqual(dirStatus.st_mode & 0o077, 0)
    }

    func testSecondHookServerCannotBindSameSocket() throws {
        let agent2 = AhaKeyAgent(
            socketPath: "/tmp/ahk-agent-test-\(UUID().uuidString.prefix(8)).sock",
            hookSocketURL: testHookURL
        )
        defer { agent2.shutdown() }

        try agent.startHookServer()

        XCTAssertThrowsError(try agent2.startHookServer()) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeHookSocketError, .lockUnavailable)
        }
    }

    func testShutdownStopsHookServer() throws {
        try agent.startHookServer()
        XCTAssertTrue(FileManager.default.fileExists(atPath: testHookURL.path))

        agent.shutdown()

        // shutdown 应 stop hookServer 并移除 socket
        XCTAssertFalse(FileManager.default.fileExists(atPath: testHookURL.path))
    }

    // MARK: - Handler 行为：Approval / Lever

    func testHandlerReturnsAutomaticApprovalWhenSwitchIsAuto() throws {
        agent.setSwitchOverride(0)

        try agent.startHookServer()
        let client = AhaKeyRuntimeHookSocketClient(socketURL: testHookURL)
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "test-1"),
            request: .approvalQuery(.init(requestID: requestID)),
            timeout: 2
        )

        XCTAssertEqual(response, .approvalDecision(requestID: requestID, decision: .automatic))
    }

    func testHandlerReturnsManualApprovalWhenSwitchIsManual() throws {
        agent.setSwitchOverride(1)

        try agent.startHookServer()
        let client = AhaKeyRuntimeHookSocketClient(socketURL: testHookURL)
        let requestID = UUID()

        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "test-2"),
            request: .approvalQuery(.init(requestID: requestID)),
            timeout: 2
        )

        XCTAssertEqual(response, .approvalDecision(requestID: requestID, decision: .manual))
    }

    func testHandlerReturnsUnavailableApprovalWhenSwitchUnknown() throws {
        try agent.startHookServer()
        let client = AhaKeyRuntimeHookSocketClient(socketURL: testHookURL)
        let requestID = UUID()

        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "test-3"),
            request: .approvalQuery(.init(requestID: requestID)),
            timeout: 2
        )

        XCTAssertEqual(response, .approvalDecision(requestID: requestID, decision: .unavailable))
    }

    func testHandlerReturnsUpLeverWhenSwitchIsAuto() throws {
        agent.setSwitchOverride(0)

        try agent.startHookServer()
        let client = AhaKeyRuntimeHookSocketClient(socketURL: testHookURL)

        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "test-4"),
            request: .leverQuery,
            timeout: 2
        )

        XCTAssertEqual(response, .leverPosition(.up))
    }

    func testHandlerReturnsDownLeverWhenSwitchIsManual() throws {
        agent.setSwitchOverride(1)

        try agent.startHookServer()
        let client = AhaKeyRuntimeHookSocketClient(socketURL: testHookURL)

        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "test-5"),
            request: .leverQuery,
            timeout: 2
        )

        XCTAssertEqual(response, .leverPosition(.down))
    }

    func testHandlerReturnsNilLeverWhenSwitchUnknown() throws {
        try agent.startHookServer()
        let client = AhaKeyRuntimeHookSocketClient(socketURL: testHookURL)

        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "test-6"),
            request: .leverQuery,
            timeout: 2
        )

        XCTAssertEqual(response, .leverPosition(nil))
    }

    func testHandlerAcknowledgesAIState() throws {
        try agent.startHookServer()
        let client = AhaKeyRuntimeHookSocketClient(socketURL: testHookURL)

        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "test-7"),
            request: .aiState(.init(event: .working, requestID: UUID())),
            timeout: 2
        )

        XCTAssertEqual(response, .acknowledged)
    }
}
