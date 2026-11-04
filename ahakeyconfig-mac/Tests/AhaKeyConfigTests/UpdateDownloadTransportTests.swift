import XCTest
import Network
@testable import AhaKeyConfig

/// Uses real TCP/URLSession: manually invoking didWriteData cannot catch a
/// delegate attached at the wrong level of an async download task.
final class UpdateDownloadTransportTests: XCTestCase {
    @MainActor
    func testRealDownloadEmitsIntermediateBytesTotalAndSpeed() async throws {
        let fixture = try SlowDownloadFixture()
        defer { fixture.stop() }
        let recorder = ProgressRecorder()
        let progress = UpdateDownloadProgress { recorder.record($0, $1, $2) }
        let (file, response) = try await progress.download(for: URLRequest(url: fixture.url), configuration: .ephemeral)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: file), fixture.payload)
        let events = recorder.snapshot()
        XCTAssertTrue(events.contains { $0.bytes > 0 && $0.bytes < fixture.payload.count },
                      "Real download must report progress while data is still arriving")
        XCTAssertEqual(events.last?.bytes, Int64(fixture.payload.count))
        XCTAssertEqual(events.last?.total, Int64(fixture.payload.count))
        XCTAssertGreaterThan(events.last?.speed ?? 0, 0)
    }

    @MainActor
    func testCancellationDuringTransferReturnsAndLeavesNoOwnedTemporaryFile() async throws {
        let fixture = try SlowDownloadFixture()
        defer { fixture.stop() }
        let initialFiles = try ownedTemporaryFiles()
        let firstProgress = expectation(description: "Real bytes arrived before cancellation")
        let recorder = ProgressRecorder()
        let progress = UpdateDownloadProgress { bytes, total, speed in
            recorder.record(bytes, total, speed)
            if recorder.snapshot().count == 1 { firstProgress.fulfill() }
        }
        let operation = Task { try await progress.download(for: URLRequest(url: fixture.url), configuration: .ephemeral) }
        await fulfillment(of: [firstProgress], timeout: 4)
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled transfer must not return an installer") }
        catch { XCTAssertTrue(error is CancellationError, "Unexpected cancellation: \(error)") }
        XCTAssertEqual(try ownedTemporaryFiles(), initialFiles)
    }

    @MainActor
    func testAlreadyCancelledTransferDoesNotStart() async throws {
        let progress = UpdateDownloadProgress { _, _, _ in XCTFail("Cancelled before start must not receive data") }
        let initialFiles = try ownedTemporaryFiles()
        let operation = Task { try await progress.download(for: URLRequest(url: URL(string: "http://127.0.0.1:1/never-start")!), configuration: .ephemeral) }
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled task must not start") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try ownedTemporaryFiles(), initialFiles)
    }

    @MainActor
    func testSecondUseCannotCancelOrCompleteAnActiveTransfer() async throws {
        let fixture = try SlowDownloadFixture()
        defer { fixture.stop() }
        let firstProgress = expectation(description: "First transfer is active")
        let recorder = ProgressRecorder()
        let progress = UpdateDownloadProgress { bytes, total, speed in
            recorder.record(bytes, total, speed)
            if recorder.snapshot().count == 1 { firstProgress.fulfill() }
        }
        let request = URLRequest(url: fixture.url)
        let first = Task { try await progress.download(for: request, configuration: .ephemeral) }
        await fulfillment(of: [firstProgress], timeout: 4)
        do { _ = try await progress.download(for: request, configuration: .ephemeral); XCTFail("One delegate owns one transfer") }
        catch { XCTAssertEqual((error as? URLError)?.code, .unknown) }
        let (file, response) = try await first.value
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: file), fixture.payload)
    }

    private func ownedTemporaryFiles() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("AhaKey-Update-") && $0.hasSuffix(".download") })
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    struct Event { let bytes: Int64; let total: Int64; let speed: Double }
    private let lock = NSLock()
    private var events: [Event] = []
    func record(_ bytes: Int64, _ total: Int64, _ speed: Double) {
        lock.lock(); defer { lock.unlock() }
        events.append(.init(bytes: bytes, total: total, speed: speed))
    }
    func snapshot() -> [Event] {
        lock.lock(); defer { lock.unlock() }; return events
    }
}

private final class SlowDownloadFixture {
    let payload = Data(repeating: 0x5a, count: 512 * 1024)
    let url: URL
    private let listener: NWListener
    private let connections: Connections

    init() throws {
        let queue = DispatchQueue(label: "AhaKey.UpdateDownloadTransportTests")
        let ready = DispatchSemaphore(value: 0)
        let connections = Connections()
        self.connections = connections
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in
            switch state { case .ready, .failed, .cancelled: ready.signal(); default: break }
        }
        let data = payload
        listener.newConnectionHandler = { connection in
            connections.add(connection)
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, error in
                guard error == nil else { connection.cancel(); return }
                let header = "HTTP/1.1 200 OK\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
                    guard error == nil else { connection.cancel(); return }
                    Self.send(data, offset: 0, connection: connection, queue: queue)
                })
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 3) == .success, let port = listener.port else {
            listener.cancel(); throw URLError(.cannotConnectToHost)
        }
        url = URL(string: "http://127.0.0.1:\(port.rawValue)/slow-download")!
    }

    private static func send(_ data: Data, offset: Int, connection: NWConnection, queue: DispatchQueue) {
        guard offset < data.count else {
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let end = min(offset + 16 * 1024, data.count)
        queue.asyncAfter(deadline: .now() + .milliseconds(30)) {
            connection.send(content: data.subdata(in: offset..<end), completion: .contentProcessed { error in
                guard error == nil else { connection.cancel(); return }
                send(data, offset: end, connection: connection, queue: queue)
            })
        }
    }
    func stop() { listener.cancel(); connections.cancelAll() }
    deinit { stop() }

    private final class Connections: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [NWConnection] = []
        func add(_ connection: NWConnection) { lock.lock(); values.append(connection); lock.unlock() }
        func cancelAll() {
            lock.lock(); let current = values; values.removeAll(); lock.unlock()
            current.forEach { $0.cancel() }
        }
    }
}
