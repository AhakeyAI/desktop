import Foundation
import Darwin
import XCTest
@testable import AhaKeyConfigShared

final class WS3NativeTerminalIdentityTests: XCTestCase {
    func testNativeSelectedTTYMatchesLiveChildProcessGroupWithoutReadingItsText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("probe.c"), executable = directory.appendingPathComponent("probe")
        // An isolated pseudo-terminal, not a user terminal or physical keyboard.
        let code = """
        #include <libproc.h>
        #include <stdio.h>
        #include <unistd.h>
        int main(void) {
            struct proc_bsdinfo own = {0}, leader = {0};
            if (proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &own, sizeof(own)) != sizeof(own)) return 1;
            if (proc_pidinfo(own.pbi_pgid, PROC_PIDTBSDINFO, 0, &leader, sizeof(leader)) != sizeof(leader)) return 2;
            char *tty = ttyname(0); if (!tty) return 3;
            printf("READY %s %u %u %llu %llu\\n", tty, own.e_tdev, own.pbi_pgid,
                (unsigned long long)leader.pbi_start_tvsec, (unsigned long long)leader.pbi_start_tvusec);
            fflush(stdout); getchar(); return 0;
        }
        """
        try Data(code.utf8).write(to: source)
        let compiler = Process(), compilerOutput = Pipe()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        compiler.arguments = [source.path, "-o", executable.path]
        compiler.standardOutput = compilerOutput; compiler.standardError = compilerOutput
        try compiler.run()
        let errors = compilerOutput.fileHandleForReading.readDataToEndOfFile(); compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0, String(data: errors, encoding: .utf8) ?? "compiler failed")
        let process = Process(), input = Pipe(), output = Pipe(), exited = expectation(description: "isolated terminal exits")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", executable.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = output
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
        let deadline = Date().addingTimeInterval(5)
        var data = Data()
        while Date() < deadline, !data.contains(10), data.count < 4096 {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 200) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 1024)
            let count = Darwin.read(descriptor.fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.contains(10) else { return XCTFail("No complete isolated terminal metadata") }
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard let start = fields.firstIndex(of: "READY"), fields.count >= start + 6,
              let device = UInt32(fields[start + 2]), let group = Int32(fields[start + 3]),
              let seconds = UInt64(fields[start + 4]), let micros = UInt64(fields[start + 5]) else { return XCTFail("Invalid isolated terminal metadata") }
        let expected = try XCTUnwrap(WS3TerminalTaskIdentity(device: device, processGroup: group, leaderStartedSeconds: seconds, leaderStartedMicroseconds: micros))
        let path = String(fields[start + 1])
        XCTAssertEqual(WS3TerminalTaskIdentity.captureTTY(path), expected)
        XCTAssertTrue(expected.isAlive())
        try input.fileHandleForWriting.write(contentsOf: Data([10])); try input.fileHandleForWriting.close()
        await fulfillment(of: [exited], timeout: 5)
    }
}
