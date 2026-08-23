import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CursorHookRuntimeClientTests: XCTestCase {
    func testServeFakeRuntimeForLiveCursor() throws {
        guard let rawDecision = ProcessInfo.processInfo.environment["AHAKEY_LIVE_DECISION"] else {
            throw XCTSkip("Only used by the authorized live Cursor smoke")
        }
        let decision: AhaKeyRuntimeHookApprovalDecision
        switch rawDecision {
        case "automatic": decision = .automatic
        case "manual": decision = .manual
        default: throw XCTSkip("Unsupported live decision")
        }
        let delay = TimeInterval(
            ProcessInfo.processInfo.environment["AHAKEY_LIVE_DELAY"] ?? "0"
        ) ?? 0
        let duration = TimeInterval(
            ProcessInfo.processInfo.environment["AHAKEY_LIVE_DURATION"] ?? "15"
        ) ?? 15
        let server = AhaKeyRuntimeHookSocketServer(
            socketURL: AhaKeyPaths.runtimeHookSocketURL
        ) { _, request in
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            guard case .approvalQuery(let query) = request else {
                return .acknowledged
            }
            return .approvalDecision(requestID: query.requestID, decision: decision)
        }
        try server.start()
        defer { server.stop() }
        print("LIVE_CURSOR_FAKE_RUNTIME_READY decision=\(rawDecision) delay=\(delay)")
        Thread.sleep(forTimeInterval: duration)
    }

    func testAgentProcessAgainstFakeRuntime() throws {
        guard ProcessInfo.processInfo.environment["AHAKEY_CURSOR_PROCESS_SMOKE"] == "1" else {
            throw XCTSkip("Run through scripts/cursor-hook-smoke.sh in an isolated HOME")
        }
        let agentPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["AHAKEY_AGENT_BINARY"]
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: agentPath))

        for tool in ["Read", "Write", "Shell", "MCP", "Task"] {
            try withRuntime(decision: .automatic) {
                let result = try runAgent(at: agentPath, tool: tool)
                XCTAssertEqual(result.status, 0, tool)
                XCTAssertEqual(result.stdout, #"{"permission":"allow"}"# + "\n", tool)
            }
            try withRuntime(decision: .manual) {
                let result = try runAgent(at: agentPath, tool: tool)
                XCTAssertEqual(result.status, 0, tool)
                XCTAssertEqual(result.stdout, "", tool)
            }
            let offline = try runAgent(at: agentPath, tool: tool)
            XCTAssertEqual(offline.status, 0, tool)
            XCTAssertEqual(offline.stdout, "", tool)
            try withRuntime(delay: 2.5, decision: .automatic) {
                let timeout = try runAgent(at: agentPath, tool: tool)
                XCTAssertEqual(timeout.status, 0, tool)
                XCTAssertEqual(timeout.stdout, "", tool)
            }
        }
    }

    private func withRuntime(
        delay: TimeInterval = 0,
        decision: AhaKeyRuntimeHookApprovalDecision,
        body: () throws -> Void
    ) throws {
        let server = AhaKeyRuntimeHookSocketServer(
            socketURL: AhaKeyPaths.runtimeHookSocketURL
        ) { _, request in
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            guard case .approvalQuery(let query) = request else {
                return .acknowledged
            }
            return .approvalDecision(requestID: query.requestID, decision: decision)
        }
        try server.start()
        defer { server.stop() }
        try body()
    }

    private func runAgent(at path: String, tool: String) throws -> (
        status: Int32,
        stdout: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["hook", "preToolUse"]
        var environment = ProcessInfo.processInfo.environment
        environment["CURSOR_VERSION"] = "3.17.8"
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        try process.run()
        let payload = try JSONSerialization.data(withJSONObject: [
            "tool_name": tool,
            "command": "must-not-be-logged",
            "cwd": "/private/must-not-be-logged",
        ])
        input.fileHandleForWriting.write(payload)
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdoutData = output.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: stdoutData, encoding: .utf8) ?? ""
        )
    }
}
