import Darwin
import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CursorHookRuntimeQueryPortTests: XCTestCase {
    private final class CountingPort: CursorHookRuntimeQueryPort {
        var callCount = 0
        var receivedRequestIDs: [UUID] = []
        let result: Result<AhaKeyRuntimeHookApprovalDecision, Error>

        init(result: Result<AhaKeyRuntimeHookApprovalDecision, Error>) {
            self.result = result
        }

        func queryApproval(requestID: UUID) throws -> AhaKeyRuntimeHookApprovalDecision {
            callCount += 1
            receivedRequestIDs.append(requestID)
            return try result.get()
        }
    }

    private enum ProbeError: Error {
        case offline
    }

    func testDecisionServiceQueriesRuntimeExactlyOnce() {
        let port = CountingPort(result: .success(.automatic))
        let requestID = UUID()
        let service = CursorHookDecisionService(queryPort: port)

        let result = service.decide(requestID: requestID)

        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(port.callCount, 1)
        XCTAssertEqual(port.receivedRequestIDs, [requestID])
    }

    func testDecisionServiceMapsManualToNativeApprovalWithoutASecondQuery() {
        let port = CountingPort(result: .success(.manual))
        let service = CursorHookDecisionService(queryPort: port)

        let result = service.decide(requestID: UUID())

        XCTAssertEqual(result.decision, .deferToNative)
        XCTAssertEqual(port.callCount, 1)
    }

    func testDecisionServiceMapsQueryFailureToUnavailableWithoutASecondQuery() {
        let port = CountingPort(result: .failure(ProbeError.offline))
        let service = CursorHookDecisionService(queryPort: port)

        let result = service.decide(requestID: UUID())

        XCTAssertEqual(result.decision, .unavailable)
        XCTAssertNil(result.standardOutput)
        XCTAssertEqual(port.callCount, 1)
    }

    func testDecisionServiceClassifiesOfflineAndTimeoutFailures() {
        let offline = CursorHookDecisionService(
            queryPort: CountingPort(
                result: .failure(AhaKeyRuntimeHookSocketError.connectionFailed(ENOENT))
            )
        ).decide(requestID: UUID())
        let timeout = CursorHookDecisionService(
            queryPort: CountingPort(
                result: .failure(AhaKeyRuntimeHookSocketError.ioFailure(EAGAIN))
            )
        ).decide(requestID: UUID())
        let missingPrivateDirectory = CursorHookDecisionService(
            queryPort: CountingPort(
                result: .failure(AhaKeyRuntimeHookSocketError.unsafeDirectory)
            )
        ).decide(requestID: UUID())

        XCTAssertEqual(offline.queryFailure, .offline)
        XCTAssertEqual(timeout.queryFailure, .timeout)
        XCTAssertEqual(missingPrivateDirectory.queryFailure, .offline)
    }

    func testFakeRuntimeCoversToolMatrixAcrossAllFourStates() {
        let tools = ["Read", "Write", "Shell", "MCP", "Task"]
        let scenarios: [(Result<AhaKeyRuntimeHookApprovalDecision, Error>, CursorHookDecision)] = [
            (.success(.automatic), .allow),
            (.success(.manual), .deferToNative),
            (.failure(AhaKeyRuntimeHookSocketError.connectionFailed(ENOENT)), .unavailable),
            (.failure(AhaKeyRuntimeHookSocketError.ioFailure(EAGAIN)), .unavailable),
        ]

        for tool in tools {
            for (runtimeResult, expectedDecision) in scenarios {
                let port = CountingPort(result: runtimeResult)
                let result = CursorHookDecisionService(queryPort: port).decide(requestID: UUID())

                XCTAssertEqual(result.decision, expectedDecision, tool)
                XCTAssertEqual(port.callCount, 1, tool)
                if expectedDecision != .allow {
                    XCTAssertNil(result.standardOutput, tool)
                }
            }
        }
    }

    func testSocketQueryClientNegotiatesAsCursorAndReturnsMatchingApproval() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-cursor-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("private/hook.sock")
        let server = AhaKeyRuntimeHookSocketServer(socketURL: socketURL) { handshake, request in
            XCTAssertEqual(handshake.client, .cursor)
            guard case .approvalQuery(let query) = request else {
                return .acknowledged
            }
            return .approvalDecision(requestID: query.requestID, decision: .automatic)
        }
        try server.start()
        defer { server.stop() }
        let client = AhaKeyRuntimeCursorHookQueryClient(
            socketURL: socketURL,
            hookBuildID: "cursor-query-test",
            timeout: 2
        )

        XCTAssertEqual(try client.queryApproval(requestID: UUID()), .automatic)
    }

    func testSocketQueryClientRejectsMismatchedRequestID() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-cursor-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("private/hook.sock")
        let server = AhaKeyRuntimeHookSocketServer(socketURL: socketURL) { _, request in
            guard case .approvalQuery = request else { return .acknowledged }
            return .approvalDecision(requestID: UUID(), decision: .automatic)
        }
        try server.start()
        defer { server.stop() }
        let client = AhaKeyRuntimeCursorHookQueryClient(
            socketURL: socketURL,
            hookBuildID: "cursor-query-test",
            timeout: 2
        )

        XCTAssertThrowsError(try client.queryApproval(requestID: UUID())) { error in
            XCTAssertEqual(error as? CursorHookRuntimeQueryError, .mismatchedResponse)
        }
    }
}
