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
        for agent in agents { _ = agent.stopLegacySocketListenerForTesting(); agent.shutdown() }
        for agent in agents {
            XCTAssertEqual(agent.legacyListenFDForTesting, -1)
            XCTAssertTrue(agent.legacyLastAcceptWorkerExitedForTesting)
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
        let flags = fcntl(pair.0, F_GETFL)
        XCTAssertGreaterThanOrEqual(flags, 0)
        XCTAssertNotEqual(flags & O_NONBLOCK, 0)
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
        let payload = Data(repeating: 0x62, count: 256 * 1024)
        let started = DispatchTime.now()
        let result = AhaKeyRuntimeLegacySocketIO.writeAll(payload, to: pair.0, timeout: 0.2)
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
        XCTAssertEqual(result, .failed(ETIMEDOUT))
        XCTAssertLessThan(elapsedNs, 1_000_000_000)
    }

    func testReadLineAssemblesFragmentedJSONUntilNewline() {
        guard let pair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else {
            return XCTFail("socketpair")
        }
        defer {
            Darwin.close(pair.0)
            Darwin.close(pair.1)
        }
        XCTAssertTrue(AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(pair.0))
        let first = Data("{\"cmd\":\"".utf8)
        let second = Data("status\"}\n".utf8)
        let done = expectation(description: "line-assembled")
        var result: AhaKeyRuntimeLegacySocketIO.ReadLineResult?
        DispatchQueue.global(qos: .userInitiated).async {
            result = AhaKeyRuntimeLegacySocketIO.readLine(pair.0, timeout: 2)
            done.fulfill()
        }
        XCTAssertEqual(first.withUnsafeBytes { Darwin.write(pair.1, $0.baseAddress!, $0.count) }, first.count)
        usleep(30_000)
        XCTAssertEqual(second.withUnsafeBytes { Darwin.write(pair.1, $0.baseAddress!, $0.count) }, second.count)
        wait(for: [done], timeout: 3)
        XCTAssertEqual(result, .line(Data("{\"cmd\":\"status\"}".utf8)))
    }

    func testReadLineFailsClosedOnOverflowAndEOFBeforeNewline() {
        guard let overflowPair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else {
            return XCTFail("socketpair")
        }
        defer {
            Darwin.close(overflowPair.0)
            Darwin.close(overflowPair.1)
        }
        XCTAssertTrue(AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(overflowPair.0))
        let blob = Data(repeating: 0x41, count: AhaKeyRuntimeLegacySocketIO.maxRequestLineBytes + 1)
        XCTAssertEqual(blob.withUnsafeBytes { Darwin.write(overflowPair.1, $0.baseAddress!, $0.count) }, blob.count)
        XCTAssertEqual(
            AhaKeyRuntimeLegacySocketIO.readLine(overflowPair.0, timeout: 1),
            .overflow
        )

        guard let eofPair = AhaKeyRuntimeLegacySocketIO.makeUnixStreamPair() else {
            return XCTFail("socketpair")
        }
        defer { Darwin.close(eofPair.0) }
        XCTAssertTrue(AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(eofPair.0))
        let partial = Data("{\"cmd\"".utf8)
        XCTAssertEqual(partial.withUnsafeBytes { Darwin.write(eofPair.1, $0.baseAddress!, $0.count) }, partial.count)
        Darwin.close(eofPair.1)
        XCTAssertEqual(
            AhaKeyRuntimeLegacySocketIO.readLine(eofPair.0, timeout: 1),
            .peerClosed
        )
    }

    func testFragmentedStatusAndPermissionReachProductionHandler() throws {
        let agent = makeAgent()
        agent.startSocketListener()
        try waitForSocket(socketPath)
        let path = try XCTUnwrap(socketPath)

        for cmd in ["status", "permission"] {
            replyGate = AhaKeyRuntimeLegacyReplyGate()
            agent.legacyReplyBeforeWriteGate = replyGate
            let line = "{\"cmd\":\"\(cmd)\"}\n"
            let bytes = Array(line.utf8)
            let split = 8
            let reply = try sendFragmentedJSON(
                path: path,
                fragments: [Data(bytes[..<split]), Data(bytes[split...])]
            )
            XCTAssertTrue(reply.contains("switchState"), "\(cmd): \(reply)")
        }

        replyGate = AhaKeyRuntimeLegacyReplyGate()
        agent.legacyReplyBeforeWriteGate = replyGate
        let followUp = try sendJSON(path: path, object: ["cmd": "status"], behavior: .readReply)
        XCTAssertTrue(followUp.contains("switchState"), followUp)
        assertListenerStillOwned(agent)
    }

    func testIdleAcceptedClientShutdownCompletesAndAllowsRestart() throws {
        let agent = makeAgent()
        for round in 0..<10 {
            agent.startSocketListener()
            try waitForSocket(socketPath)
            let client = try unixConnect(try XCTUnwrap(socketPath))
            let acceptedDeadline = Date().addingTimeInterval(1)
            while agent.legacyActiveClientCountForTesting == 0 && Date() < acceptedDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertGreaterThan(agent.legacyActiveClientCountForTesting, 0, "round \(round) never accepted")
            let started = DispatchTime.now()
            XCTAssertTrue(agent.stopLegacySocketListenerForTesting(), "round \(round)")
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
            XCTAssertLessThan(elapsedNs, 1_000_000_000, "round \(round) shutdown \(elapsedNs)ns")
            XCTAssertTrue(agent.legacyLastAcceptWorkerExitedForTesting)
            XCTAssertEqual(agent.legacyListenFDForTesting, -1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(socketPath)))
            Darwin.close(client)
        }
        XCTAssertEqual(agent.legacyOwnerUnlinkCountForTesting, 10)

        agent.startSocketListener()
        try waitForSocket(socketPath)
        replyGate = AhaKeyRuntimeLegacyReplyGate()
        agent.legacyReplyBeforeWriteGate = replyGate
        let reply = try sendJSON(
            path: try XCTUnwrap(socketPath),
            object: ["cmd": "status"],
            behavior: .readReply
        )
        XCTAssertTrue(reply.contains("switchState"), reply)
        assertListenerStillOwned(agent)
    }

    func testListenFailureDoesNotPublishOwner() throws {
        let agent = makeAgent()
        agent.legacyListenHookForTesting = { _ in
            errno = EINVAL
            return -1
        }
        agent.startSocketListener()
        XCTAssertEqual(agent.legacyListenFDForTesting, -1)
        XCTAssertEqual(agent.legacyOwnerUnlinkCountForTesting, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(socketPath)))
        XCTAssertThrowsError(try unixConnect(try XCTUnwrap(socketPath)))

        agent.legacyListenHookForTesting = nil
        agent.startSocketListener()
        try waitForSocket(socketPath)
        XCTAssertGreaterThanOrEqual(agent.legacyListenFDForTesting, 0)
        XCTAssertTrue(agent.stopLegacySocketListenerForTesting())
        XCTAssertEqual(agent.legacyOwnerUnlinkCountForTesting, 1)
        XCTAssertEqual(agent.legacyListenFDForTesting, -1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(socketPath)))
    }

    func testShutdownClosesListenerAndUnlinksPath() throws {
        let agent = makeAgent()
        agent.startSocketListener()
        try waitForSocket(socketPath)
        XCTAssertGreaterThanOrEqual(agent.legacyListenFDForTesting, 0)
        agent.shutdown()
        XCTAssertEqual(agent.legacyListenFDForTesting, -1)
        XCTAssertTrue(agent.legacyLastAcceptWorkerExitedForTesting)
        XCTAssertEqual(agent.legacyOwnerUnlinkCountForTesting, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(socketPath)))
        XCTAssertThrowsError(try unixConnect(try XCTUnwrap(socketPath)))
        agent.shutdown()
        XCTAssertEqual(agent.legacyOwnerUnlinkCountForTesting, 1)
        XCTAssertTrue(agent.legacyLastAcceptWorkerExitedForTesting)
        XCTAssertEqual(agent.legacyListenFDForTesting, -1)
    }

    func testRapidListenerRestartRejectsStaleAcceptWorker() throws {
        let agent = makeAgent()
        var previousGeneration: UInt64 = 0
        for _ in 0..<20 {
            agent.startSocketListener()
            try waitForSocket(socketPath)
            let generation = agent.legacyListenGenerationForTesting
            XCTAssertNotEqual(generation, previousGeneration)
            previousGeneration = generation
            XCTAssertGreaterThanOrEqual(agent.legacyListenFDForTesting, 0)
            replyGate = AhaKeyRuntimeLegacyReplyGate()
            agent.legacyReplyBeforeWriteGate = replyGate
            let reply = try sendJSON(
                path: try XCTUnwrap(socketPath),
                object: ["cmd": "status"],
                behavior: .readReply
            )
            XCTAssertTrue(reply.contains("switchState"), reply)
            XCTAssertTrue(agent.stopLegacySocketListenerForTesting())
            XCTAssertTrue(agent.legacyLastAcceptWorkerExitedForTesting)
            XCTAssertEqual(agent.legacyListenFDForTesting, -1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(socketPath)))
        }
        XCTAssertEqual(agent.legacyOwnerUnlinkCountForTesting, 20)
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

    private final class LockedClientIO: @unchecked Sendable {
        private let lock = NSLock()
        private var fd: Int32 = -1
        private var reply = ""
        private var error: Error?

        func store(fd: Int32) {
            lock.lock()
            self.fd = fd
            lock.unlock()
        }

        func takeFD() -> Int32 {
            lock.lock()
            defer { lock.unlock() }
            let value = fd
            fd = -1
            return value
        }

        func peekFD() -> Int32 {
            lock.lock()
            defer { lock.unlock() }
            return fd
        }

        func setReply(_ value: String) {
            lock.lock()
            reply = value
            lock.unlock()
        }

        func setError(_ error: Error) {
            lock.lock()
            self.error = error
            lock.unlock()
        }

        func snapshot() -> (reply: String, error: Error?) {
            lock.lock()
            defer { lock.unlock() }
            return (reply, error)
        }
    }

    @discardableResult
    private func sendJSON(path: String, object: [String: Any], behavior: ClientBehavior) throws -> String {
        let box = LockedClientIO()
        let connected = expectation(description: "legacy-client-written")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fd = try self.unixConnect(path)
                try self.writeJSONLine(fd, object: object)
                box.store(fd: fd)
            } catch {
                box.setError(error)
            }
            connected.fulfill()
        }
        wait(for: [connected], timeout: 3)
        if let error = box.snapshot().error { throw error }

        guard replyGate.waitUntilAccepted(timeout: 3) else {
            replyGate.releaseWrite()
            var leftover = box.takeFD()
            AhaKeyRuntimeLegacySocketIO.closeOnce(&leftover)
            struct HandlerDidNotAccept: Error {}
            throw HandlerDidNotAccept()
        }

        switch behavior {
        case .closeImmediately:
            var fd = box.takeFD()
            AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
            replyGate.releaseWrite()
            XCTAssertTrue(replyGate.waitUntilWriteFinished(timeout: 3))
            return ""
        case .closeAfter(let milliseconds):
            usleep(useconds_t(milliseconds * 1_000))
            var fd = box.takeFD()
            AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
            replyGate.releaseWrite()
            XCTAssertTrue(replyGate.waitUntilWriteFinished(timeout: 3))
            return ""
        case .readReply:
            replyGate.releaseWrite()
            let finished = expectation(description: "legacy-client-read")
            DispatchQueue.global(qos: .userInitiated).async {
                var fd = box.peekFD()
                var buf = [UInt8](repeating: 0, count: 1_024)
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let n = Darwin.read(fd, &buf, buf.count)
                if n > 0 {
                    box.setReply(String(bytes: buf.prefix(Int(n)), encoding: .utf8) ?? "")
                } else {
                    box.setError(POSIXError(.ETIMEDOUT))
                }
                fd = box.takeFD()
                AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
                finished.fulfill()
            }
            wait(for: [finished], timeout: 5)
            XCTAssertTrue(replyGate.waitUntilWriteFinished(timeout: 3))
            let snapshot = box.snapshot()
            if let error = snapshot.error { throw error }
            return snapshot.reply
        }
    }

    private func writeJSONLine(_ fd: Int32, object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object, options: [])
        var line = payload
        line.append(0x0A)
        try writeAll(line, to: fd)
    }

    private func sendFragmentedJSON(path: String, fragments: [Data]) throws -> String {
        let box = LockedClientIO()
        let connected = expectation(description: "legacy-fragment-written")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fd = try self.unixConnect(path)
                box.store(fd: fd)
                for (index, part) in fragments.enumerated() {
                    try self.writeAll(part, to: fd)
                    if index + 1 < fragments.count {
                        usleep(30_000)
                    }
                }
            } catch {
                box.setError(error)
            }
            connected.fulfill()
        }
        wait(for: [connected], timeout: 3)
        if let error = box.snapshot().error { throw error }

        guard replyGate.waitUntilAccepted(timeout: 3) else {
            replyGate.releaseWrite()
            var leftover = box.takeFD()
            AhaKeyRuntimeLegacySocketIO.closeOnce(&leftover)
            struct HandlerDidNotAccept: Error {}
            throw HandlerDidNotAccept()
        }

        replyGate.releaseWrite()
        let finished = expectation(description: "legacy-fragment-read")
        DispatchQueue.global(qos: .userInitiated).async {
            var fd = box.peekFD()
            var buf = [UInt8](repeating: 0, count: 1_024)
            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 {
                box.setReply(String(bytes: buf.prefix(Int(n)), encoding: .utf8) ?? "")
            } else {
                box.setError(POSIXError(.ETIMEDOUT))
            }
            fd = box.takeFD()
            AhaKeyRuntimeLegacySocketIO.closeOnce(&fd)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertTrue(replyGate.waitUntilWriteFinished(timeout: 3))
        let snapshot = box.snapshot()
        if let error = snapshot.error { throw error }
        return snapshot.reply
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let wrote = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return Darwin.write(fd, base, ptr.count)
        }
        if wrote != data.count {
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
