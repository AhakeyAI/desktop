import Foundation

/// Admission before an exclusive restore operation, without consuming a command turn.
@MainActor
public enum RestoreChannelAdmission {
    public enum Failure: Error, LocalizedError {
        case timeout
        public var errorDescription: String? {
            NSLocalizedString("键盘通信仍忙，请稍后重新读取。本次未执行恢复。", comment: "")
        }
    }
    public static func waitUntilIdle(timeout: Duration = .seconds(5),
        isIdle: () -> Bool, checkSession: () throws -> Void,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) }) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            try checkSession()
            if isIdle() { return }
            guard ContinuousClock.now < deadline else { throw Failure.timeout }
            try await pause()
        }
    }
}
