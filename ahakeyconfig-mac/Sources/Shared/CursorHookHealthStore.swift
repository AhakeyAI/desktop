import Darwin
import Foundation

public enum CursorHookHealthEventCategory: String, Sendable {
    case toolPermission = "tool_permission"
}

public enum CursorHookLatencyBucket: String, Sendable {
    case under50ms = "under_50ms"
    case from50To199ms = "50_199ms"
    case from200To999ms = "200_999ms"
    case atLeast1000ms = "at_least_1000ms"

    public static func classify(seconds: TimeInterval) -> CursorHookLatencyBucket {
        switch max(0, seconds) {
        case ..<0.05: return .under50ms
        case ..<0.20: return .from50To199ms
        case ..<1.00: return .from200To999ms
        default: return .atLeast1000ms
        }
    }
}

/// 常开健康日志只接受有界枚举和版本；API 本身不接受 prompt、command、cwd、路径或环境。
public final class CursorHookHealthStore {
    public let maxFileSize: Int
    public let maxArchiveCount: Int
    private let writer: RotatingLogFile

    public init(
        fileURL: URL,
        maxFileSize: Int = 5 * 1024 * 1024,
        maxArchiveCount: Int = 2
    ) {
        self.maxFileSize = maxFileSize
        self.maxArchiveCount = maxArchiveCount
        self.writer = RotatingLogFile(
            fileURL: fileURL,
            maxFileSize: maxFileSize,
            maxArchiveCount: maxArchiveCount
        )
    }

    public func record(
        eventCategory: CursorHookHealthEventCategory,
        decision: CursorHookDecision,
        latency: TimeInterval,
        failure: CursorHookQueryFailure?,
        hookVersion: String,
        runtimeProtocolVersion: String
    ) throws {
        let object: [String: Any] = [
            "eventCategory": eventCategory.rawValue,
            "decision": decisionValue(decision),
            "latencyBucket": CursorHookLatencyBucket.classify(seconds: latency).rawValue,
            "timeoutCount": failure == .timeout ? 1 : 0,
            "offlineCount": failure == .offline ? 1 : 0,
            "hookVersion": boundedVersion(hookVersion),
            "runtimeProtocolVersion": boundedVersion(runtimeProtocolVersion),
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else { return }
        try withProcessLock {
            try writer.append(line + "\n")
        }
    }

    private func decisionValue(_ decision: CursorHookDecision) -> String {
        switch decision {
        case .allow: return "allow"
        case .deferToNative: return "defer_to_native"
        case .unavailable: return "unavailable"
        }
    }

    private func boundedVersion(_ value: String) -> String {
        String(value.unicodeScalars.prefix(64))
    }

    private func withProcessLock(_ body: () throws -> Void) throws {
        let directory = writer.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let lockPath = writer.fileURL.path + ".lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        try body()
    }
}
