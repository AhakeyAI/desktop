import Foundation

/// Actual acknowledged wire bytes, including sector padding. Estimation starts
/// after BEGIN, and is display-only: it never changes pacing or retry policy.
public struct WS3ResourceTransferProgress: Equatable {
    public let completedBytes: Int
    public let totalBytes: Int
    public let elapsedSeconds: TimeInterval
    public init(completedBytes: Int, totalBytes: Int, elapsedSeconds: TimeInterval) {
        self.totalBytes = max(0, totalBytes)
        self.completedBytes = min(max(0, completedBytes), self.totalBytes)
        self.elapsedSeconds = elapsedSeconds
    }
    public var bytesPerSecond: Double? {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 1, completedBytes > 0 else { return nil }
        let rate = Double(completedBytes) / elapsedSeconds
        return rate.isFinite && rate > 0 ? rate : nil
    }
    public var estimatedRemainingSeconds: TimeInterval? {
        guard totalBytes > 0 else { return nil }
        if completedBytes == totalBytes { return 0 }
        guard let rate = bytesPerSecond else { return nil }
        return Double(totalBytes - completedBytes) / rate
    }
}
