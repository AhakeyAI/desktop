import Foundation

/// The write closure returns only after a successful device ACK. A fresh status
/// read is still required; ACK alone is never reported as applied.
@MainActor
public enum ConfirmedModeChange {
    public enum Failure: Error, Equatable, LocalizedError {
        case invalidMode
        case mismatch(expected: UInt8, actual: UInt8)
        public var errorDescription: String? {
            switch self {
            case .invalidMode: return NSLocalizedString("设备返回的模式无效。", comment: "")
            case .mismatch(let expected, let actual):
                return String(format: NSLocalizedString("键盘读回为 Mode %@，未确认切换到 Mode %@。", comment: ""), String(describing: actual + 1), String(describing: expected + 1))
            }
        }
    }

    public static func run(
        target: UInt8,
        checkSession: () throws -> Void,
        readMode: () async throws -> UInt8,
        writeMode: (UInt8) async throws -> Void
    ) async throws -> UInt8 {
        guard target < 4 else { throw Failure.invalidMode }
        try Task.checkCancellation()
        try checkSession()
        let current = try await readMode()
        try Task.checkCancellation()
        try checkSession()
        guard current < 4 else { throw Failure.invalidMode }
        if current == target { return current }
        try await writeMode(target)
        try Task.checkCancellation()
        try checkSession()
        let actual = try await readMode()
        try Task.checkCancellation()
        try checkSession()
        guard actual < 4 else { throw Failure.invalidMode }
        guard actual == target else { throw Failure.mismatch(expected: target, actual: actual) }
        return actual
    }
}
