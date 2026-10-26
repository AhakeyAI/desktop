import Foundation

/// UI feedback for an already-paused policy. It never grants or restores rights.
public enum ApprovalRevocationFeedback {
    public enum Completion: Equatable { case confirmed, notConfirmed, superseded }

    @MainActor
    public static func wait(_ initial: ApprovalAutomationControl.RevocationOutcome,
                            directory: URL = ApprovalAutomationControl.productionDirectory,
                            timeout: Duration = .seconds(8),
                            isCurrent: () -> Bool,
                            pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }) async -> Completion {
        guard !Task.isCancelled, isCurrent() else { return .superseded }
        switch initial {
        case .complete: return .confirmed
        case .failed: return .notConfirmed
        case .recovering: break
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            guard !Task.isCancelled, isCurrent() else { return .superseded }
            do {
                if try !CodexDesktopLeverState(directory: directory).hasPendingRecovery() { return .confirmed }
            } catch { return .notConfirmed }
            guard ContinuousClock.now < deadline else { return .notConfirmed }
            do { try await pause() }
            catch is CancellationError { return .superseded }
            catch { return .notConfirmed }
        }
    }
}
