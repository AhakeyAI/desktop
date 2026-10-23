import Foundation

/// An absolute typing deadline, including connection setup and response body.
/// URLRequest.timeoutInterval alone can restart when more bytes arrive.
enum InteractiveCloudRequest {
    static func data(for request: URLRequest, session: URLSession, budget: TimeInterval) async throws -> (Data, URLResponse) {
        let flight = Flight()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error { flight.finish(.failure(error)) }
                    else if let data, let response { flight.finish(.success((data, response))) }
                    else { flight.finish(.failure(URLError(.badServerResponse))) }
                }
                flight.start(task, continuation: continuation, budget: budget)
            }
        }, onCancel: { flight.finish(.failure(CancellationError())) })
    }

    /// All completion paths, including cancellation before start, settle once.
    private final class Flight: @unchecked Sendable {
        typealias Output = (Data, URLResponse)
        private let lock = NSLock()
        private var outcome: Result<Output, Error>?
        private var continuation: CheckedContinuation<Output, Error>?
        private var task: URLSessionDataTask?
        private var timer: DispatchWorkItem?

        func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<Output, Error>, budget: TimeInterval) {
            lock.lock()
            if let outcome {
                lock.unlock()
                task.cancel()
                continuation.resume(with: outcome)
                return
            }
            self.task = task
            self.continuation = continuation
            let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(URLError(.timedOut))) }
            self.timer = timer
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget, execute: timer)
            task.resume()
        }

        func finish(_ result: Result<Output, Error>) {
            lock.lock()
            guard outcome == nil else { lock.unlock(); return }
            outcome = result
            let continuation = continuation, task = task, timer = timer
            self.continuation = nil; self.task = nil; self.timer = nil
            lock.unlock()
            timer?.cancel()
            task?.cancel()
            continuation?.resume(with: result)
        }
    }
}
