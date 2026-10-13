import Foundation

@MainActor
public enum ConfirmedStandbySetting {
    public static let supportedMinutes: [UInt16] = [0, 30, 60, 120]
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidValue
        case mismatch(expected: UInt16, actual: UInt16)
        public var errorDescription: String? {
            switch self {
            case .invalidValue: return "待机时间只支持 0、30、60、120 分钟。"
            case .mismatch(let expected, let actual): return "键盘读回 \(actual) 分钟，未确认设置为 \(expected) 分钟。"
            }
        }
    }

    public static func request(minutes: UInt16) -> Data? {
        guard supportedMinutes.contains(minutes) else { return nil }
        return Data([0xAA, 0xBB, 0x95, UInt8(minutes & 0xFF), UInt8(minutes >> 8), 0xCC, 0xDD])
    }

    public static func run(target: UInt16, checkSession: () throws -> Void,
                           read: () async throws -> UInt16,
                           write: (UInt16) async throws -> Void) async throws -> UInt16 {
        guard supportedMinutes.contains(target) else { throw Failure.invalidValue }
        try checkSession()
        let current = try await read()
        try checkSession()
        guard supportedMinutes.contains(current) else { throw Failure.invalidValue }
        if current == target { return current }
        try await write(target)
        try checkSession()
        let actual = try await read()
        try checkSession()
        guard supportedMinutes.contains(actual) else { throw Failure.invalidValue }
        guard actual == target else { throw Failure.mismatch(expected: target, actual: actual) }
        return actual
    }
}
