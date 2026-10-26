import XCTest
import Darwin
@testable import AhaKeyConfigShared

final class KimiDesktopInstanceDiscoveryTests: XCTestCase {
    private let id = "01" + String(repeating: "A", count: 24)
    private let now: Int64 = 1_800_000_000_000
    private func fields() -> [String: Any] {
        ["server_id": id, "pid": 1234, "host": "127.0.0.1", "port": 23456,
         "started_at": now - 20_000, "heartbeat_at": now - 1000, "host_version": "2.3.2"]
    }
    private func data(_ values: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: values) }
    private func directory() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("kimi-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("server/instances"), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }
    func testStrictRegistrationAcceptsOfficialShapeWithoutGivingSessionAuthority() throws {
        let value = try XCTUnwrap(KimiDesktopInstanceDiscovery.Registration.parse(data(fields()), filename: id + ".json", nowMilliseconds: now))
        XCTAssertEqual(value.host, "127.0.0.1"); XCTAssertEqual(value.port, 23456)
        XCTAssertEqual(value.serverVersion, "2.3.2")
        XCTAssertNil(KimiDesktopInstanceDiscovery.Registration.parse(try data(fields()), filename: "other.json", nowMilliseconds: now))
    }
    func testRemoteHostsMalformedNumbersAndStaleRecordsAreRejected() throws {
        let bad: [(String, Any)] = [("host", "localhost"), ("host", "192.168.1.2"), ("host", "127.0.0.1/path"),
            ("pid", true), ("pid", "1234"), ("pid", 1234.5), ("pid", -1), ("port", false), ("port", 65536),
            ("heartbeat_at", now - 46_000), ("heartbeat_at", now + 6000), ("started_at", now + 10_000),
            ("server_id", String(repeating: "A", count: 26))]
        for (key, value) in bad {
            var object = fields(); object[key] = value
            XCTAssertNil(KimiDesktopInstanceDiscovery.Registration.parse(try data(object), filename: id + ".json", nowMilliseconds: now), key)
        }
    }
    func testDiscoveryRequiresVerifierAndDoesNotPromoteUnsignedRegistrations() throws {
        let home = try directory(), file = home.appendingPathComponent("server/instances/" + id + ".json")
        try data(fields()).write(to: file)
        let rejected = KimiDesktopInstanceDiscovery.scan(homes: [home], nowMilliseconds: now, verify: { _ in nil })
        XCTAssertTrue(rejected.instances.isEmpty); XCTAssertEqual(rejected.unverifiedRegistrations, 1)
        let accepted = KimiDesktopInstanceDiscovery.scan(homes: [home], nowMilliseconds: now, verify: { value in
            .init(process: WS3ProcessInstance(pid: value.pid, seconds: 1_799_999_950, microseconds: 0)!, installedVersion: "1.1.3")
        })
        XCTAssertEqual(accepted.instances.count, 1)
        XCTAssertEqual(accepted.instances.first?.homeDirectory, home)
    }
    func testSymlinkAndWritableRecordNeverReachVerifier() throws {
        let home = try directory(), records = home.appendingPathComponent("server/instances"), target = home.appendingPathComponent("outside.json")
        try data(fields()).write(to: target)
        let file = records.appendingPathComponent(id + ".json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        var verified = 0
        _ = KimiDesktopInstanceDiscovery.scan(homes: [home], nowMilliseconds: now, verify: { _ in verified += 1; return nil })
        XCTAssertEqual(verified, 0)
        try FileManager.default.removeItem(at: file)
        try data(fields()).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: file.path)
        _ = KimiDesktopInstanceDiscovery.scan(homes: [home], nowMilliseconds: now, verify: { _ in verified += 1; return nil })
        XCTAssertEqual(verified, 0)
    }
    func testConfiguredHomesDoNotSearchArbitraryUserDirectories() {
        let home = URL(fileURLWithPath: "/Users/example")
        XCTAssertEqual(KimiDesktopInstanceDiscovery.configuredHomes(environment: [:], userHome: home).map(\.path), ["/Users/example/.kimi-code"])
        XCTAssertEqual(KimiDesktopInstanceDiscovery.configuredHomes(environment: ["KIMI_CODE_HOME": "relative"], userHome: home).count, 1)
        XCTAssertEqual(KimiDesktopInstanceDiscovery.configuredHomes(environment: ["KIMI_CODE_HOME": "/custom/kimi"], userHome: home).map(\.path), ["/custom/kimi", "/Users/example/.kimi-code"])
    }
    private func listener(wildcard: Bool = false) throws -> (Int32, UInt16) {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: wildcard ? 0 : UInt32(0x7F000001).bigEndian)
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0, listen(descriptor, 1) == 0 else { close(descriptor); throw POSIXError(.EIO) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let captured = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        guard captured == 0 else { close(descriptor); throw POSIXError(.EIO) }
        return (descriptor, UInt16(bigEndian: address.sin_port))
    }
    func testKernelListenerProofMatchesOnlyCurrentProcessAndExactLoopbackBinding() throws {
        let (descriptor, port) = try listener(); defer { close(descriptor) }
        let process = try XCTUnwrap(WS3ProcessInstance.capture(getpid()))
        XCTAssertTrue(KimiDesktopInstanceDiscovery.ownsListener(process: process, host: "127.0.0.1", port: port))
        let stale = WS3ProcessInstance(pid: process.pid, seconds: process.seconds + 1, microseconds: process.microseconds)!
        XCTAssertFalse(KimiDesktopInstanceDiscovery.ownsListener(process: stale, host: "127.0.0.1", port: port))
        XCTAssertFalse(KimiDesktopInstanceDiscovery.ownsListener(process: process, host: "localhost", port: port))
    }
    func testIPv6LoopbackListenerHasKernelOwnershipProof() throws {
        let descriptor = socket(AF_INET6, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw XCTSkip("IPv6 is unavailable on this test host") }
        defer { close(descriptor) }
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6); address.sin6_addr = in6addr_loopback
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
        } }
        guard bound == 0 else { throw XCTSkip("IPv6 loopback is unavailable on this test host") }
        XCTAssertEqual(listen(descriptor, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        let captured = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        } }
        XCTAssertEqual(captured, 0)
        let process = try XCTUnwrap(WS3ProcessInstance.capture(getpid()))
        XCTAssertTrue(KimiDesktopInstanceDiscovery.ownsListener(process: process, host: "::1", port: UInt16(bigEndian: address.sin6_port)))
    }

    func testWildcardListenerIsNotAProofOfLoopbackOnlyServer() throws {
        let (descriptor, port) = try listener(wildcard: true); defer { close(descriptor) }
        let process = try XCTUnwrap(WS3ProcessInstance.capture(getpid()))
        XCTAssertFalse(KimiDesktopInstanceDiscovery.ownsListener(process: process, host: "127.0.0.1", port: port))
    }
}
