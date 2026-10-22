import Foundation
import Darwin

/// TTY/process-group provenance, not command text or a guessed session ID.
/// The leader birth time prevents PID reuse from highlighting another task.
public struct WS3TerminalTaskIdentity: Codable, Equatable, Sendable {
    public let device: UInt32
    public let processGroup: Int32
    public let leaderStartedSeconds: UInt64
    public let leaderStartedMicroseconds: UInt64

    public init?(device: UInt32, processGroup: Int32, leaderStartedSeconds: UInt64, leaderStartedMicroseconds: UInt64) {
        guard device != UInt32.max, processGroup > 1, leaderStartedSeconds > 0, leaderStartedMicroseconds < 1_000_000 else { return nil }
        self.device = device; self.processGroup = processGroup
        self.leaderStartedSeconds = leaderStartedSeconds; self.leaderStartedMicroseconds = leaderStartedMicroseconds
    }
    public init?(dictionary: [String: String]) {
        guard let device = dictionary["terminalDevice"].flatMap(UInt32.init),
              let group = dictionary["terminalGroup"].flatMap(Int32.init),
              let seconds = dictionary["terminalLeaderSeconds"].flatMap(UInt64.init),
              let microseconds = dictionary["terminalLeaderMicroseconds"].flatMap(UInt64.init) else { return nil }
        self.init(device: device, processGroup: group, leaderStartedSeconds: seconds, leaderStartedMicroseconds: microseconds)
    }
    private enum CodingKeys: String, CodingKey { case device, processGroup, leaderStartedSeconds, leaderStartedMicroseconds }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let identity = Self(device: try values.decode(UInt32.self, forKey: .device),
            processGroup: try values.decode(Int32.self, forKey: .processGroup),
            leaderStartedSeconds: try values.decode(UInt64.self, forKey: .leaderStartedSeconds),
            leaderStartedMicroseconds: try values.decode(UInt64.self, forKey: .leaderStartedMicroseconds)) else {
            throw DecodingError.dataCorruptedError(forKey: .processGroup, in: values, debugDescription: "Invalid terminal identity")
        }
        self = identity
    }
    public var dictionary: [String: String] {
        ["terminalDevice": String(device), "terminalGroup": String(processGroup),
         "terminalLeaderSeconds": String(leaderStartedSeconds), "terminalLeaderMicroseconds": String(leaderStartedMicroseconds)]
    }
    public static func captureCurrentProcess() -> Self? {
        guard let info = processInfo(getpid()), info.pbi_flags & UInt32(PROC_FLAG_CTTY) != 0,
              info.pbi_pgid <= Int32.max else { return nil }
        return capture(device: info.e_tdev, group: Int32(info.pbi_pgid))
    }
    /// Only a native foreground-provider may supply the selected tab's TTY.
    /// This reads its device/group metadata, never terminal input or output.
    public static func captureTTY(_ path: String) -> Self? {
        guard validTTYPath(path) else { return nil }
        var state = stat()
        guard lstat(path, &state) == 0, state.st_mode & S_IFMT == S_IFCHR else { return nil }
        let device = UInt32(bitPattern: state.st_rdev)
        // tcgetpgrp on another session's slave returns ENOTTY on macOS. Read
        // the kernel's TTY-filtered BSD metadata instead; never open its stream.
        var pids = [Int32](repeating: 0, count: 256)
        let capacity = pids.count * MemoryLayout<Int32>.size
        let bytes = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_TTY_ONLY), device, $0.baseAddress, Int32($0.count)) }
        guard bytes > 0, bytes < capacity, Int(bytes).isMultiple(of: MemoryLayout<Int32>.size) else { return nil }
        for pid in pids.prefix(Int(bytes) / MemoryLayout<Int32>.size) where pid > 1 {
            guard let info = processInfo(pid), info.e_tdev == device, info.pbi_uid == geteuid(),
                  info.e_tpgid > 1, info.e_tpgid <= Int32.max,
                  let identity = capture(device: device, group: Int32(info.e_tpgid)),
                  let confirmed = processInfo(pid), confirmed.e_tdev == device,
                  confirmed.e_tpgid == info.e_tpgid, confirmed.pbi_start_tvsec == info.pbi_start_tvsec,
                  confirmed.pbi_start_tvusec == info.pbi_start_tvusec else { continue }
            return identity
        }
        return nil
    }
    public static func validTTYPath(_ path: String) -> Bool {
        path.hasPrefix("/dev/ttys") && (10...64).contains(path.utf8.count) &&
            path.dropFirst(9).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    public func isAlive() -> Bool {
        Self.capture(device: device, group: processGroup) == self
    }
    private static func capture(device: UInt32, group: Int32) -> Self? {
        guard group > 1, device != UInt32.max,
              let leader = processInfo(group), leader.pbi_pgid == UInt32(group), leader.e_tdev == device,
              leader.pbi_uid == geteuid() else { return nil }
        return Self(device: device, processGroup: group, leaderStartedSeconds: leader.pbi_start_tvsec,
            leaderStartedMicroseconds: leader.pbi_start_tvusec)
    }
    private static func processInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }
}
