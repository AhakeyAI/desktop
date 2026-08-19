import Foundation

public enum AhaKeyUSBHIDChannel: UInt8, Sendable {
    case command = 0xA1
    case data = 0xA2
}

public enum AhaKeyUSBHIDReportCodec {
    public static let reportSize = 64
    public static let maximumPayloadSize = reportSize - 2

    public static func report(channel: AhaKeyUSBHIDChannel, payload: Data) throws -> Data {
        guard payload.count <= maximumPayloadSize else {
            throw AhaKeyUSBHIDReportCodecError.payloadTooLarge
        }
        var bytes = [UInt8](repeating: 0, count: reportSize)
        bytes[0] = channel.rawValue
        bytes[1] = UInt8(payload.count)
        bytes.replaceSubrange(2 ..< 2 + payload.count, with: payload)
        return Data(bytes)
    }

    public static func dataReports(for data: Data) throws -> [Data] {
        try stride(from: 0, to: data.count, by: maximumPayloadSize).map { offset in
            let end = min(offset + maximumPayloadSize, data.count)
            return try report(channel: .data, payload: Data(data[offset ..< end]))
        }
    }

    /// Extracts the first complete AhaKey protocol frame from the declared USB HID payload.
    /// Firmware responses are raw zero-padded frames; enveloped responses are also accepted for compatibility.
    public static func protocolFrame(from report: Data) -> Data? {
        if let frame = extractProtocolFrame(from: report) { return frame }
        guard report.count >= 2 else { return nil }
        let payloadLength = Int(report[report.startIndex + 1])
        guard payloadLength <= maximumPayloadSize, report.count >= payloadLength + 2 else { return nil }
        let payload = Data(report.dropFirst(2).prefix(payloadLength))
        return extractProtocolFrame(from: payload)
    }

    private static func extractProtocolFrame(from payload: Data) -> Data? {
        guard let start = payload.indices.first(where: { index in
            index + 1 < payload.endIndex && payload[index] == 0xAA && payload[index + 1] == 0xBB
        }) else { return nil }
        var end = start + 3
        while end + 1 < payload.endIndex {
            if payload[end] == 0xCC, payload[end + 1] == 0xDD {
                return Data(payload[start ... end + 1])
            }
            end += 1
        }
        return nil
    }
}

public enum AhaKeyUSBHIDReportCodecError: LocalizedError {
    case payloadTooLarge

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge:
            return "USB HID payload exceeds the 62-byte report limit"
        }
    }
}

public enum AhaKeyConfigurationTransportRoute: Equatable, Sendable {
    case ble
    case usb
}

public struct AhaKeyConfigurationTransportContext: Equatable {
    public let protocolMode: AhaKeyProtocolMode
    public let usbAttached: Bool
    public let configurationSessionOwned: Bool
    public let usbDeviceIdentifier: String?
    public let negotiatedDeviceIdentifier: String?
    public let forceBLE: Bool

    public init(
        protocolMode: AhaKeyProtocolMode,
        usbAttached: Bool,
        configurationSessionOwned: Bool,
        usbDeviceIdentifier: String?,
        negotiatedDeviceIdentifier: String?,
        forceBLE: Bool
    ) {
        self.protocolMode = protocolMode
        self.usbAttached = usbAttached
        self.configurationSessionOwned = configurationSessionOwned
        self.usbDeviceIdentifier = usbDeviceIdentifier
        self.negotiatedDeviceIdentifier = negotiatedDeviceIdentifier
        self.forceBLE = forceBLE
    }
}

public enum AhaKeyConfigurationTransportSelector {
    public static func route(_ context: AhaKeyConfigurationTransportContext) -> AhaKeyConfigurationTransportRoute {
        guard !context.forceBLE,
              context.protocolMode.allowsUSBConfigurationTransport,
              context.usbAttached,
              context.configurationSessionOwned,
              matchingDeviceIdentifiers(context) else {
            return .ble
        }
        return .usb
    }

    private static func matchingDeviceIdentifiers(_ context: AhaKeyConfigurationTransportContext) -> Bool {
        guard let usb = normalized(context.usbDeviceIdentifier),
              let negotiated = normalized(context.negotiatedDeviceIdentifier) else {
            return false
        }
        return usb == negotiated
    }

    private static func normalized(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty, normalized != "—" else { return nil }
        return normalized
    }
}
