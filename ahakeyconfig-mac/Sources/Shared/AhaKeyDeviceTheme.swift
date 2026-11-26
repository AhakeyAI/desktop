import Foundation

public enum AhaKeyDeviceTheme: UInt8, Codable, CaseIterable, Sendable {
    case dark = 0
    case light = 1
}

/// Device UI appearance is independent of App appearance, key modes and artwork.
public enum AhaKeyDeviceThemeProtocol {
    public static let query = Data([0xAA, 0xBB, 0x88, 0x04, 0xCC, 0xDD])

    public static func set(_ theme: AhaKeyDeviceTheme) -> Data {
        Data([0xAA, 0xBB, 0x8E, 0x02, theme.rawValue, 0xCC, 0xDD])
    }

    public static func parseRead(_ frame: Data) -> AhaKeyDeviceTheme? {
        let bytes = Array(frame)
        guard bytes.count == 12,
              Array(bytes[0..<7]) == [0xAA, 0xBB, 0x88, 0x00, 0x04, 0x01, 0x03],
              Array(bytes[8..<12]) == [0x55, 0x49, 0xCC, 0xDD] else { return nil }
        return AhaKeyDeviceTheme(rawValue: bytes[7])
    }

    public static func isSetRequest(_ frame: Data) -> Bool {
        AhaKeyDeviceTheme.allCases.contains { set($0) == frame }
    }

    public static func isSuccessAck(_ frame: Data) -> Bool {
        frame == Data([0xAA, 0xBB, 0x8E, 0x00, 0xCC, 0xDD])
    }
}

public enum DeviceThemeTransaction {
    public enum Failure: Error, LocalizedError {
        case unconfirmed, rejected
        public var errorDescription: String? {
            switch self {
            case .unconfirmed: return NSLocalizedString("屏幕主题未确认，请连接稳定后重新读取；旧固件可能需要升级。", comment: "")
            case .rejected: return NSLocalizedString("键盘暂未接受主题设置，请稍后重新读取并重试。", comment: "")
            }
        }
    }

    public struct Result: Equatable {
        public let theme: AhaKeyDeviceTheme
        public let saved: Bool
    }

    /// Validate on both sides of every await; a cancelled or replaced connection
    /// cannot authorize the next command or publish a successful result.
    @MainActor
    public static func run(selection: AhaKeyDeviceTheme? = nil,
                           validate: () throws -> Void,
                           exchange: (Data) async throws -> Data) async throws -> Result {
        func read() async throws -> AhaKeyDeviceTheme {
            try Task.checkCancellation()
            try validate()
            let frame = try await exchange(AhaKeyDeviceThemeProtocol.query)
            try Task.checkCancellation()
            try validate()
            guard let theme = AhaKeyDeviceThemeProtocol.parseRead(frame) else { throw Failure.unconfirmed }
            return theme
        }
        let initial = try await read()
        guard let selection else { return Result(theme: initial, saved: false) }
        try validate()
        let ack = try await exchange(AhaKeyDeviceThemeProtocol.set(selection))
        try Task.checkCancellation()
        try validate()
        guard AhaKeyDeviceThemeProtocol.isSuccessAck(ack) else { throw Failure.rejected }
        let actual = try await read()
        return Result(theme: actual, saved: actual == selection)
    }
}
