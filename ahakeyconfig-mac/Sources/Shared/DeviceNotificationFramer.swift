import Foundation

/// Reassembles verified CP4D responses while leaving legacy notifications on
/// their existing path. Keep one instance per BLE characteristic and reset it
/// when the connection changes.
public struct DeviceNotificationFramer {
    private var decoder = DeviceFrameDecoder()
    private var lastChunkAt: TimeInterval?
    private let assemblyTimeout: TimeInterval = 2

    public init() {}

    public mutating func reset() {
        decoder.reset()
        lastChunkAt = nil
    }

    public mutating func append(
        _ notification: Data,
        at time: TimeInterval = Date().timeIntervalSince1970
    ) -> [Data] {
        if let lastChunkAt, time - lastChunkAt > assemblyTimeout { reset() }
        let bytes = [UInt8](notification)
        let startsKnownFrame = bytes.first == 0xAA && (
            bytes.count == 1 ||
            (bytes[1] == 0xBB && (bytes.count == 2 || DeviceFrameDecoder.recognizes(bytes[2])))
        )
        if decoder.isAssembling || startsKnownFrame {
            let frames = decoder.append(notification)
            lastChunkAt = decoder.isAssembling ? time : nil
            return frames
        }
        return [notification]
    }
}
