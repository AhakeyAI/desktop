import Foundation
import XCTest
@testable import AhaKeyConfig

final class WCHISPProcessRunnerTests: XCTestCase {
    private final class DelayedRead: @unchecked Sendable {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var didDelay = false
        func read(_ handle: FileHandle) -> Data {
            let chunk = handle.availableData
            lock.lock()
            let delay = !chunk.isEmpty && !didDelay
            if delay { didDelay = true }
            lock.unlock()
            if delay {
                started.signal()
                _ = release.wait(timeout: .now() + 5)
            }
            return chunk
        }
    }

    @MainActor
    func testExitedProcessWaitsForAlreadyReadOutputBeforeReturning() async throws {
        let gate = DelayedRead()
        defer { gate.release.signal() }
        let runner = WCHISPProcessRunner(readOutput: gate.read)
        let premature = expectation(description: "Do not return while output consumption is unfinished")
        premature.isInverted = true
        let finished = expectation(description: "Process result received")
        var result: Result<WCHISPCommandResult, Error>?
        let task = Task {
            do { result = .success(try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'Chip: CH582\\n'; sleep 0.03"])) }
            catch { result = .failure(error) }
            premature.fulfill()
            finished.fulfill()
        }
        let readerStarted = await Task.detached { gate.started.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(readerStarted)
        await fulfillment(of: [premature], timeout: 0.2)
        gate.release.signal()
        await fulfillment(of: [finished], timeout: 3)
        await task.value
        let value = try XCTUnwrap(result).get()
        XCTAssertEqual(value.status, 0)
        XCTAssertEqual(value.output, "Chip: CH582\n")
    }
    func testDrainsLargeUTF8OutputAndStderrBeforeReturningFailureStatus() async throws {
        let runner = WCHISPProcessRunner()
        let line = "键盘😀诊断输出\n"
        let result = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c",
            "printf 'BEGIN\\n'; i=0; while [ \"$i\" -lt 8192 ]; do printf '键盘😀诊断输出\\n'; i=$((i+1)); done; printf 'END\\n' >&2; exit 9"])
        XCTAssertEqual(result.status, 9)
        XCTAssertEqual(result.output, "BEGIN\n" + String(repeating: line, count: 8192) + "END\n")
    }

}
