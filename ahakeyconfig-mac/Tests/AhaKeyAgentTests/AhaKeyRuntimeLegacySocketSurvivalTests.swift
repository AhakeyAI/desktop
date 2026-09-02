import Darwin
import Foundation
import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

final class AhaKeyRuntimeLegacySocketSurvivalTests: XCTestCase {
    private var testRoot: URL!
    private var agents: [AhaKeyAgent] = []
    private var socketPath: String!

    override func setUp() {
        super.setUp()
        testRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-legacy-sock-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for agent in agents { agent.shutdown() }
        agents.removeAll()
        if let testRoot { try? FileManager.default.removeItem(at: testRoot) }
        super.tearDown()
    }

    func testClosedPeerWriteSurvivesDefaultSIGPIPEInChild() throws {
        let probe = try locateBuiltProduct("AhaKeyRuntimeLegacySocketProbe")
        let process = Process()
        process.executableURL = probe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0)
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
                    continue
                }
                if n < 0 && errno == EINTR { continue }
                break
            }
            done.fulfill()
        }
        XCTAssertEqual(AhaKeyRuntimeLegacySocketIO.writeAll(payload, to: pair.0), .completed)
        Darwin.shutdown(pair.0, SHUT_WR)
        wait(for: [done], timeout: 5)
        lock.lock()
        let snapshot = collected
        lock.unlock()
        XCTAssertEqual(snapshot, payload)
    }

    func testStatusClientDisconnectDoesNotBlockLaterRequest() throws {
        let agent = makeAgent()
        agent.startSocketListener()
        try waitForSocket(socketPath)

        try sendJSON(path: try XCTUnwrap(socketPath), object: ["cmd": "status"], behavior: .closeImmediately)
        let pause = expectation(description: "status-async-window")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.7) { pause.fulfill() }
        wait(for: [pause], timeout: 3)

        let reply = try sendJSON(
            path: try XCTUnwrap(socketPath),
            object: ["cmd": "unknown"],
            behavior: .readReply
        )
        XCTAssertTrue(reply.contains("unknown cmd"))
    }

    func testLegacySocketStressMatrixKeepsListenerAlive() throws {
        let agent = makeAgent()
        agent.startSocketListener()
        try waitForSocket(socketPath)
        let path = try XCTUnwrap(socketPath)

        var cases: [(cmd: String, behavior: ClientBehavior)] = []
        cases += Array(repeating: (cmd: "status", behavior: .closeImmediately), count: 10)
        cases += Array(repeating: (cmd: "permission", behavior: .closeImmediately), count: 10)
        cases += Array(repeating: (cmd: "unknown", behavior: .closeImmediately), count: 40)
        cases += Array(repeating: (cmd: "unknown", behavior: .closeAfter(milliseconds: 15)), count: 20)
        cases += Array(repeating: (cmd: "unknown", behavior: .readReply), count: 20)
        XCTAssertEqual(cases.count, 100)

        for item in cases {
            let reply = try sendJSON(
                path: path,
                object: ["cmd": item.cmd],
                behavior: item.behavior
            )
            if item.behavior == .readReply {
                XCTAssertTrue(reply.contains("unknown cmd"), reply)
            }
        }

        let finalReply = try sendJSON(
            path: path,
            object: ["cmd": "unknown"],
            behavior: .readReply
        )
        XCTAssertTrue(finalReply.contains("unknown cmd"), finalReply)
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
        agents.append(agent)
        return agent
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
        var reply = ""
        var error: Error?
    }

    @discardableResult
    private func sendJSON(path: String, object: [String: Any], behavior: ClientBehavior) throws -> String {
        let box = SendBox()
        let finished = expectation(description: "legacy-client-io")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                box.reply = try self.sendJSONBlocking(path: path, object: object, behavior: behavior)
            } catch {
                box.error = error
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 8)
        if let error = box.error { throw error }
        return box.reply
    }

    @discardableResult
    private func sendJSONBlocking(path: String, object: [String: Any], behavior: ClientBehavior) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: object, options: [])
        var line = payload
        line.append(0x0A)
        let fd = try unixConnect(path)
        defer {
            var owned = fd
            AhaKeyRuntimeLegacySocketIO.closeOnce(&owned)
        }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let wrote = line.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return Darwin.write(fd, base, ptr.count)
        }
        XCTAssertEqual(wrote, line.count)
        switch behavior {
        case .closeImmediately:
            return ""
        case .closeAfter(let milliseconds):
            usleep(useconds_t(milliseconds * 1_000))
            return ""
        case .readReply:
            var buf = [UInt8](repeating: 0, count: 1_024)
            let n = Darwin.read(fd, &buf, buf.count)
            XCTAssertGreaterThan(n, 0, "legacy socket reply timed out or empty")
            return String(bytes: buf.prefix(max(0, Int(n))), encoding: .utf8) ?? ""
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
