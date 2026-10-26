import Foundation
import CoreFoundation
import AppKit
import Security
import Darwin

/// Discovery only: no credentials, HTTP, session resume, or permission writes.
/// A signed listener is not proof that it owns any particular conversation.
public enum KimiDesktopInstanceDiscovery {
    public struct Registration: Equatable, Sendable {
        public let serverID: String
        public let pid: Int32
        public let host: String
        public let port: UInt16
        public let startedMilliseconds: Int64
        public let heartbeatMilliseconds: Int64
        public let serverVersion: String?

        public static func parse(_ data: Data, filename: String, nowMilliseconds: Int64) -> Self? {
            guard data.count <= 16_384, nowMilliseconds > 0, nowMilliseconds <= 9_007_199_254_740_991,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["server_id"] as? String, validID(id), filename == id + ".json",
                  let pid = integer(object["pid"]), pid > 1, pid <= Int32.max,
                  let host = object["host"] as? String, ["127.0.0.1", "::1"].contains(host),
                  let port = integer(object["port"]), port > 0, port <= 65535,
                  let started = integer(object["started_at"]), started > 0,
                  let heartbeat = integer(object["heartbeat_at"]), heartbeat >= started,
                  heartbeat <= 9_007_199_254_740_991,
                  (-5_000...45_000).contains(nowMilliseconds - heartbeat),
                  started <= nowMilliseconds + 5_000 else { return nil }
            let version = object["host_version"] as? String
            guard object["host_version"] == nil || (version != nil && version!.utf8.count <= 64 &&
                !version!.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)) else { return nil }
            return Self(serverID: id, pid: Int32(pid), host: host, port: UInt16(port),
                        startedMilliseconds: started, heartbeatMilliseconds: heartbeat, serverVersion: version)
        }
        fileprivate static func validID(_ value: String) -> Bool {
            let bytes = Array(value.utf8), alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
            return bytes.count == 26 && (UInt8(48)...55).contains(bytes[0]) && bytes.allSatisfy(alphabet.contains)
        }
        private static func integer(_ value: Any?) -> Int64? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int64(number.stringValue)
        }
    }
    public struct Instance: Equatable, Sendable {
        public let registration: Registration
        public let process: WS3ProcessInstance
        /// Installation metadata, not a claim that serverVersion identifies exact bundle bytes.
        public let installedVersion: String
        public let homeDirectory: URL
    }
    struct ProcessEvidence {
        let process: WS3ProcessInstance
        let installedVersion: String
    }
    public struct Report: Sendable {
        public let instances: [Instance]
        public let unverifiedRegistrations: Int
        public let inspectedDirectories: Int
        public let limitReached: Bool
    }
    public static func configuredHomes(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       userHome: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var homes = [userHome.appendingPathComponent(".kimi-code", isDirectory: true)]
        if let override = environment["KIMI_CODE_HOME"], override.hasPrefix("/"), !override.contains("\0") {
            homes.insert(URL(fileURLWithPath: override, isDirectory: true), at: 0)
        }
        var seen = Set<String>()
        return homes.map { $0.resolvingSymlinksInPath().standardizedFileURL }.filter { seen.insert($0.path).inserted }
    }
    public static func scan(homes: [URL], now: Date = Date()) -> Report {
        let milliseconds = now.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds > 0, milliseconds <= 9_007_199_254_740_991 else {
            return Report(instances: [], unverifiedRegistrations: 0, inspectedDirectories: 0, limitReached: false)
        }
        return scan(homes: homes, nowMilliseconds: Int64(milliseconds), verify: verifyDesktop)
    }
    static func scan(homes: [URL], nowMilliseconds: Int64,
                     verify: (Registration) -> ProcessEvidence?) -> Report {
        var found: [Instance] = [], rejected = 0, directories = 0, limited = false
        var visited = Set<String>()
        for home in homes.prefix(8) {
            if Task.isCancelled { break }
            let server = home.appendingPathComponent("server", isDirectory: true)
            let directory = server.appendingPathComponent("instances", isDirectory: true)
            guard home.isFileURL, visited.insert(directory.path).inserted, trustedDirectory(home),
                  trustedDirectory(server), trustedDirectory(directory),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            directories += 1
            let records = names.filter { $0.hasSuffix(".json") && Registration.validID(String($0.dropLast(5))) }.sorted()
            if records.count > 128 { limited = true }
            for name in records.prefix(128) {
                if Task.isCancelled { break }
                guard let data = readRecord(directory.appendingPathComponent(name)),
                      let record = Registration.parse(data, filename: name, nowMilliseconds: nowMilliseconds),
                      let proof = verify(record), proof.process.pid == record.pid else { rejected += 1; continue }
                let instance = Instance(registration: record, process: proof.process,
                    installedVersion: proof.installedVersion, homeDirectory: home)
                if !found.contains(where: { $0.process == instance.process && $0.registration.serverID == record.serverID }) {
                    found.append(instance)
                }
            }
        }
        return Report(instances: found, unverifiedRegistrations: rejected,
                      inspectedDirectories: directories, limitReached: limited || homes.count > 8)
    }
    private static func trustedDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR &&
            info.st_uid == geteuid() && info.st_mode & 0o022 == 0
    }
    private static func readRecord(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == geteuid(), before.st_mode & 0o022 == 0,
              before.st_size > 0, before.st_size <= 16_384 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(before.st_size)), offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            }
            guard count > 0 else { return nil }
            offset += count
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_ino == after.st_ino, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { return nil }
        return Data(bytes)
    }
    private static func verifyDesktop(_ record: Registration) -> ProcessEvidence? {
        guard let process = WS3ProcessInstance.capture(record.pid), process.seconds < UInt64(Int64.max / 1000),
              record.startedMilliseconds >= Int64(process.seconds * 1000 + process.microseconds / 1000) - 1000,
              let app = NSRunningApplication(processIdentifier: record.pid),
              app.bundleIdentifier == "com.kimi.code.desktop", let bundle = app.bundleURL,
              let version = Bundle(url: bundle)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty, version.utf8.count <= 64 else { return nil }
        let text = "identifier \"com.kimi.code.desktop\" and anchor apple generic and certificate leaf[subject.OU] = \"2J9472RW75\""
        var requirement: SecRequirement?, code: SecCode?
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: record.pid)] as CFDictionary,
                                            SecCSFlags(), &code) == errSecSuccess,
              let requirement, let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess,
              ownsListener(process: process, host: record.host, port: record.port), process.isAlive else { return nil }
        return ProcessEvidence(process: process, installedVersion: version)
    }
    /// Kernel metadata only: no TCP connection or request is sent.
    static func ownsListener(process: WS3ProcessInstance, host: String, port: UInt16) -> Bool {
        guard port > 0, ["127.0.0.1", "::1"].contains(host), process.isAlive else { return false }
        let required = proc_pidinfo(process.pid, PROC_PIDLISTFDS, 0, nil, 0)
        let stride = MemoryLayout<proc_fdinfo>.stride
        guard required > 0, Int(required) <= stride * 4096 else { return false }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(required) / stride + 16)
        let capacity = descriptors.count * stride
        let received = descriptors.withUnsafeMutableBytes { proc_pidinfo(process.pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32(capacity)) }
        guard received > 0, Int(received) < capacity, Int(received) % stride == 0 else { return false }
        for fd in descriptors.prefix(Int(received) / stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var socket = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(process.pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socket, size) == size,
                  socket.psi.soi_kind == SOCKINFO_TCP, socket.psi.soi_protocol == IPPROTO_TCP,
                  socket.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let inet = socket.psi.soi_proto.pri_tcp.tcpsi_ini
            guard UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_lport)) == port else { continue }
            let matches: Bool
            if host == "127.0.0.1", socket.psi.soi_family == AF_INET {
                matches = UInt32(bigEndian: inet.insi_laddr.ina_46.i46a_addr4.s_addr) == 0x7F000001
            } else if host == "::1", socket.psi.soi_family == AF_INET6 {
                var address = inet.insi_laddr.ina_6
                matches = withUnsafeBytes(of: &address) { $0.count == 16 && $0.dropLast().allSatisfy { $0 == 0 } && $0.last == 1 }
            } else { matches = false }
            if matches { return process.isAlive }
        }
        return false
    }
}
