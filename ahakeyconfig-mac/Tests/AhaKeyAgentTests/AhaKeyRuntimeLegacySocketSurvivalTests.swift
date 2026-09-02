import Darwin
import Foundation
import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

final class AhaKeyRuntimeLegacySocketSurvivalTests: XCTestCase {
    private var testRoot: URL!
    private var agents: [AhaKeyAgent] = []
    private var socketPath: String!
    private var replyGate: AhaKeyRuntimeLegacyReplyGate!

    override func setUp() {
        super.setUp()
        testRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-legacy-sock-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        replyGate = AhaKeyRuntimeLegacyReplyGate()
        socketPath = nil
        agents = []
    }

    override func tearDown() {
        for agent in agents { agent.shutdown() }
        for agent in agents {
            XCTAssertEqual(agent.legacyListenFDForTesting, -1)
        }
        if let socketPath {
            XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        }
        agents.removeAll()
        if let testRoot { try? FileManager.default.removeItem(at: testRoot) }
        super.tearDown()
    }

    func testInRepoRawWriteDiesWithSIGPIPEAndWriterSurvives() throws {
        let probe = try locateBuiltProduct("AhaKeyRuntimeLegacySocketProbe")
        let raw = try runProbe(probe, arguments: ["raw"])
        XCTAssertTrue(
            (raw.reason == .uncaughtSignal && raw.status == SIGPIPE)
                || (raw.reason == .exit && raw.status == 141),
            "raw write must die SIGPIPE (signal 13 or exit 141), got reason=\(raw.reason.rawValue) status=\(raw.status)"
        )

        let writer = try runProbe(probe, arguments: ["writer"])
        XCTAssertEqual(writer.reason, .exit)
        XCTAssertEqual(writer.status, 0)
    }

    func testWriteAllTreatsEPIPEAsPeerClosed() {
        guard let pair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else {
            return XCTFail("socketpair")
        }
        XCTAssertTrue(AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(pair.0))
        Darwin.close(pair.1)
        let result = AhaKeyRuntimeLegacySocketIO.writeAll(Data("{\"cmd\":\"status\"}\n".utf8), to: pair.0)
        XCTAssertEqual(result, .peerClosed)
        var fd = pair.0
        AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
        AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
        XCTAssertEqual(fd, -1)
    }

    func testWriteAllCompletesAcrossPartialWrites() {
        guard let pair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else {
            return XCTFail("socketpair")
        }
        defer {
            Darwin.close(pair.0)
            Darwin.close(pair.1)
        }
        XCTAssertTrue(AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(pair.0))
        let flags = fcntl(pair.0, F_GETFL)
        XCTAssertGreaterThanOrEqual(flags, 0)
        XCTAssertEqual(fcntl(pair.0, F_SETFL, flags | O_NONBLOCK), 0)
        let payload = Data(repeating: 0x61, count: 128 * 1024)
        let lock = NSLock()
        var collected = Data()
        let done = expectation(description: "reader-drained")
        DispatchQueue.global(qos: .userInitiated).async {
            var buf = [UInt8](repeating: 0, count: 32)
            while true {
                let n = read(pair.1, &buf, buf.count)
                if n > 0 {
                    lock.lock()
                    collected.append(contentsOf: buf.prefix(n))
                    lock.unlock()
                    usleep(200)
                    continue
                }
                if n < 0 && errno == EINTR { continue }
                break
            }
            done.fulfill()
        }
        XCTAssertEqual(
            AhaKeyRuntimeLegacySocketIO.writeAll(payload, to: pair.0, timeout: 5),
            .completed
        )
        Darwin.shutdown(pair.0, SHUT_WR)
        wait(for: [done], timeout: 5)
        lock.lock()
        let snapshot = collected
        lock.unlock()
        XCTAssertEqual(snapshot, payload)
    }

    func testWriteAllTimesOutWhenPeerDoesNotRead() {
        guard let pair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else {
            return XCTFail("socketpair")
        }
        defer {
            Darwin.close(pair.0)
            Darwin.close(pair.1)
        }
        XCTAssertTrue(AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(pair.0))
        let flags = fcntl(pair.0, F_GETFL)
        XCTAssertGreaterThanOrEqual(flags, 0)
        XCTAssertEqual(fcntl(pair.0, F_SETFL, flags | O_NONBLOCK), 0)
        let payload = Data(repeating: 0x62, count: 256 * 1024)
        let started = Date()
        let result = AhaKeyRuntimeLegacySocketIO.writeAll(payload, to: pair.0, timeout: 0.2)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(result, .failed(ETIMEDOUT))
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testShutdownClosesListenerAndUnlinksPath() throws {
        let agent = makeAgent()
        agent.startSocketListener()
        try waitForSocket(socketPath)
        XCTAssertGreaterThanOrEqual(agent.legacyListenFDForTesting, 0)
        agent.shutdown()
        XCTAssertEqual(agent.legacyListenFDForTesting, -1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(socketPath)))
        XCTAssertThrowsError(try unixConnect(try XCTUnwrap(socketPath)))
    }

    func testStatusClientDisconnectDoesNotBlockLaterRequest() throws {
        let agent = makeAgent()
        agent.startSocketListener()
        try waitForSocket(socketPath)
        let path = try XCTUnwrap(socketPath)

        try sendJSON(path: path, object: ["cmd": "status"], behavior: .closeImmediately)
        let reply = try sendJSON(path: path, object: ["cmd": "status"], behavior: .readReply)
        XCTAssertTrue(reply.contains("switchState"), reply)
        assertListenerStillOwned(agent)
    }

    func testLegacySocketStressMatrixKeepsListenerAlive() throws {
        let agent = makeAgent()
        agent.startSocketListener()
        try waitForSocket(socketPath)
        let path = try XCTUnwrap(socketPath)

        var cases: [(cmd: String, behavior: ClientBehavior)] = []
        cases += Array(repeating: (cmd: "status", behavior: .closeImmediately), count: 20)
        cases += Array(repeating: (cmd: "permission", behavior: .closeImmediately), count: 20)
        cases += Array(repeating: (cmd: "status", behavior: .closeAfter(milliseconds: 15)), count: 15)
        cases += Array(repeating: (cmd: "permission", behavior: .closeAfter(milliseconds: 15)), count: 15)
        cases += Array(repeating: (cmd: "status", behavior: .readReply), count: 15)
        cases += Array(repeating: (cmd: "permission", behavior: .readReply), count: 15)
        XCTAssertEqual(cases.count, 100)

        for item in cases {
            replyGate = AhaKeyRuntimeLegacyReplyGate()
            agent.legacyReplyBeforeWriteGate = replyGate
            let reply = try sendJSON(path: path, object: ["cmd": item.cmd], behavior: item.behavior)
            if item.behavior == .readReply {
                XCTAssertTrue(reply.contains("switchState"), reply)
            }
        }

        replyGate = AhaKeyRuntimeLegacyReplyGate()
        agent.legacyReplyBeforeWriteGate = replyGate
        let finalReply = try sendJSON(path: path, object: ["cmd": "status"], behavior: .readReply)
        XCTAssertTrue(finalReply.contains("switchState"), finalReply)
        assertListenerStillOwned(agent)
    }

    private enum ClientBehavior: Equatable {
        case closeImmediately
        case closeAfter(milliseconds: Int)
        case readReply
    }

    private func makeAgent() -> AhaKeyAgent {
        socketPath = testRoot.appendingPathComponent("legacy-\(UUID().uuidString.prefix(6)).sock").path
        let agent = AhaKeyAgent(
            socketPath: socketPath,
            hookSocketURL: testRoot.appendingPathComponent("hook-\(UUID().uuidString.prefix(6)).sock"),
            enableRuntimeModules: false
        )
        agent.legacyReplyBeforeWriteGate = replyGate
        agents.append(agent)
        return agent
    }

    private func assertListenerStillOwned(_ agent: AhaKeyAgent) {
        XCTAssertGreaterThanOrEqual(agent.legacyListenFDForTesting, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
    }

    private func waitForSocket(_ path: String?) throws {
        let path = try XCTUnwrap(path)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        struct MissingSocket: Error {}
        throw MissingSocket()
    }

    private final class SendBox: @unchecked Sendable {
        var fd: Int32 = -1
        var reply = ""
        var error: Error?
    }

    @discardableResult
    private func sendJSON(path: String, object: [String: Any], behavior: ClientBehavior) throws -> String {
        let box = SendBox()
        let connected = expectation(description: "legacy-client-written")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                box.fd = try self.unixConnect(path)
                try self.writeJSONLine(box.fd, object: object)
            } catch {
                box.error = error
            }
            connected.fulfill()
        }
        wait(for: [connected], timeout: 3)
        if let error = box.error { throw error }

        guard replyGate.waitUntilAccepted(timeout: 3) else {
            replyGate.releaseWrite()
            struct HandlerDidNotAccept: Error {}
            throw HandlerDidNotAccept()
        }

        switch behavior {
        case .closeImmediately:
            AhaKeyRuntimeLegacySocketIO.closeOnce(&box.fd)
            replyGate.releaseWrite()
            return ""
        case .closeAfter(let milliseconds):
            usleep(useconds_t(milliseconds * 1_000))
            AhaKeyRuntimeLegacySocketIO.closeOnce(&box.fd)
            replyGate.releaseWrite()
            return ""
        case .readReply:
            replyGate.releaseWrite()
            let finished = expectation(description: "legacy-client-read")
            DispatchQueue.global(qos: .userInitiated).async {
                var buf = [UInt8](repeating: 0, count: 1_024)
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                _ = setsockopt(box.fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let n = Darwin.read(box.fd, &buf, buf.count)
                if n > 0 {
                    box.reply = String(bytes: buf.prefix(Int(n)), encoding: .utf8) ?? ""
                } else {
                    box.error = POSIXError(.ETIMEDOUT)
                }
                AhaKeyRuntimeLegacySocketIO.closeOnce(&box.fd)
                finished.fulfill()
            }
            wait(for: [finished], timeout: 5)
            if let error = box.error { throw error }
            return box.reply
        }
    }

    private func writeJSONLine(_ fd: Int32, object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object, options: [])
        var line = payload
        line.append(0x0A)
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let wrote = line.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return Darwin.write(fd, base, ptr.count)
        }
        if wrote != line.count {
            throw POSIXError(.EIO)
        }
    }

    private func unixConnect(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ECONNREFUSED) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bound = path.withCString { ptr -> Bool in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let buf = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                let length = strnlen(ptr, maxLen - 1)
                guard length < maxLen else { return false }
                memcpy(buf, ptr, length + 1)
                return true
            }
        }
        guard bound else {
            Darwin.close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            Darwin.close(fd)
            throw POSIXError(.ECONNREFUSED)
        }
        return fd
    }

    private func runProbe(_ url: URL, arguments: [String]) throws -> (reason: Process.TerminationReason, status: Int32) {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return (process.terminationReason, process.terminationStatus)
    }

    private func locateBuiltProduct(_ name: String) throws -> URL {
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = dir.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<12 {
            for config in ["debug", "release"] {
                let candidate = root
                    .appendingPathComponent(".build")
                    .appendingPathComponent(config)
                    .appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
            root.deleteLastPathComponent()
        }
        struct MissingProduct: Error {}
        throw MissingProduct()
    }
}
