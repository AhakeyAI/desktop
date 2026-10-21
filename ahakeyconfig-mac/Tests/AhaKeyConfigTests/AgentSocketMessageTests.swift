import Darwin
import Foundation
import XCTest
@testable import AhaKeyConfig

final class AgentSocketMessageTests: XCTestCase {
    private func query(chunks: [Data]) throws -> Data? {
        let path = "/tmp/aha-task-\(UUID().uuidString).sock"
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(listener, 0)
        defer { close(listener); unlink(path) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { source in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                _ = strcpy(UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self), source)
            }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 1) == 0 else { XCTFail("temporary socket failed"); return nil }
        let served = expectation(description: "temporary peer finished")
        DispatchQueue.global().async {
            defer { served.fulfill() }
            let peer = accept(listener, nil, nil)
            guard peer >= 0 else { return }
            defer { close(peer) }
            var noSigPipe: Int32 = 1
            setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            var input = [UInt8](repeating: 0, count: 256)
            _ = read(peer, &input, input.count)
            for chunk in chunks {
                _ = chunk.withUnsafeBytes { write(peer, $0.baseAddress!, chunk.count) }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        let result = AgentManager.querySocketData(socketPath: path, command: "presentation_tasks")
        wait(for: [served], timeout: 3)
        return result
    }

    func testReadsFragmentedLargeMessageThroughNewlineWithoutTruncation() throws {
        let body = Data(("{\"test\":\"" + String(repeating: "a", count: 1800) + "\"}").utf8)
        XCTAssertEqual(try query(chunks: [Data(body.prefix(100)), Data(body.dropFirst(100)), Data([10])]), body)
    }

    func testRejectsUnterminatedAndOversizedMessages() throws {
        XCTAssertNil(try query(chunks: [Data("{\"partial\":".utf8)]))
        XCTAssertNil(try query(chunks: [Data(repeating: 65, count: 8192), Data([10])]))
        XCTAssertNil(AgentManager.querySocketData(socketPath: String(repeating: "x", count: 200), command: "status"))
    }
}
