import Foundation

/// Test-only barrier for production `status` / `permission` replies.
///
/// The handler marks accepted, then waits off the main thread until the test
/// closes or reads the client and releases the write. Production leaves this nil.
public final class AhaKeyRuntimeLegacyReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var accepted = false
    private let proceed = DispatchSemaphore(value: 0)

    public init() {}

    public func markAcceptedAndWaitForRelease() {
        lock.lock()
        accepted = true
        lock.unlock()
        proceed.wait()
    }

    public func waitUntilAccepted(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let done = accepted
            lock.unlock()
            if done { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return false
    }

    public func releaseWrite() {
        proceed.signal()
    }
}
