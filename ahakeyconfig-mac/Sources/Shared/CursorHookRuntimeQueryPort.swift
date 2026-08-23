import Darwin
import Foundation

/// Cursor Hook 对 Runtime 的唯一查询 seam。
public protocol CursorHookRuntimeQueryPort: AnyObject {
    func queryApproval(requestID: UUID) throws -> AhaKeyRuntimeHookApprovalDecision
}

/// 每个工具事件只调用一次 query port，再把结果交给纯 reducer。
public struct CursorHookDecisionService {
    private let queryPort: any CursorHookRuntimeQueryPort

    public init(queryPort: any CursorHookRuntimeQueryPort) {
        self.queryPort = queryPort
    }

    public func decide(requestID: UUID) -> CursorHookDecisionResult {
        do {
            return CursorHookDecisionReducer.reduce(
                try queryPort.queryApproval(requestID: requestID)
            )
        } catch {
            return CursorHookDecisionResult(
                decision: .unavailable,
                standardOutput: nil,
                queryFailure: Self.classify(error)
            )
        }
    }

    private static func classify(_ error: Error) -> CursorHookQueryFailure {
        guard let socketError = error as? AhaKeyRuntimeHookSocketError else {
            return .invalidResponse
        }
        switch socketError {
        case .connectionFailed(let code):
            return code == ETIMEDOUT ? .timeout : .offline
        case .ioFailure(let code):
            return code == EAGAIN || code == ETIMEDOUT ? .timeout : .invalidResponse
        case .pathTooLong, .unsafeDirectory, .unsafeExistingPath,
             .socketCreationFailed, .bindFailed, .listenFailed,
             .permissionHardeningFailed, .unsafeSocket, .lockUnavailable:
            return .offline
        default:
            return .invalidResponse
        }
    }
}

public enum CursorHookRuntimeQueryError: Error, Equatable, Sendable {
    case mismatchedResponse
}

/// 通过 WBS 5.2 restricted Hook socket 查询 Cursor approval。
public final class AhaKeyRuntimeCursorHookQueryClient: CursorHookRuntimeQueryPort {
    private let socketClient: AhaKeyRuntimeHookSocketClient
    private let handshake: AhaKeyRuntimeHookHandshake
    private let timeout: TimeInterval

    public init(socketURL: URL, hookBuildID: String, timeout: TimeInterval = 2) {
        precondition(timeout > 0)
        self.socketClient = AhaKeyRuntimeHookSocketClient(socketURL: socketURL)
        self.handshake = AhaKeyRuntimeHookHandshake(
            protocolVersion: .current,
            client: .cursor,
            hookBuildID: hookBuildID
        )
        self.timeout = timeout
    }

    public func queryApproval(requestID: UUID) throws -> AhaKeyRuntimeHookApprovalDecision {
        let response = try socketClient.exchange(
            handshake: handshake,
            request: .approvalQuery(.init(requestID: requestID)),
            timeout: timeout
        )
        guard case .approvalDecision(let responseID, let decision) = response,
              responseID == requestID else {
            throw CursorHookRuntimeQueryError.mismatchedResponse
        }
        return decision
    }
}
