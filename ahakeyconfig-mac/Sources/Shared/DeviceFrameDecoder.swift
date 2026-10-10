import Foundation

/// Reassembles the accepted WS2 CP4D response frames from arbitrary BLE chunks.
/// The protocol has no universal length field, so only commands with a known
/// response shape are decoded here. Unknown commands must keep their existing
/// transport path until their response contract is established.
public struct DeviceFrameDecoder {
    private var bytes: [UInt8] = []
    private let maximumFrameLength = 64

    public init() {}

    public var isAssembling: Bool { !bytes.isEmpty }

    public static func recognizes(_ command: UInt8) -> Bool {
        switch command {
        case 0x00, 0x87, 0x95, 0x96, 0x97, 0x9F: return true
        default: return false
        }
    }

    public mutating func reset() {
        bytes.removeAll(keepingCapacity: true)
    }

    public mutating func append(_ chunk: Data) -> [Data] {
        bytes.append(contentsOf: chunk)
        var frames: [Data] = []

        while !bytes.isEmpty {
            guard let start = bytes.indices.first(where: {
                bytes[$0] == 0xAA && $0 + 1 < bytes.count && bytes[$0 + 1] == 0xBB
            }) else {
                bytes = bytes.last == 0xAA ? [0xAA] : []
                break
            }
            if start > 0 { bytes.removeFirst(start) }
            guard bytes.count >= 4 else { break }

            switch frameLength() {
            case .incomplete:
                if bytes.count > maximumFrameLength { bytes.removeFirst() } else { return frames }
            case .invalid:
                bytes.removeFirst()
            case .complete(let length):
                guard bytes.count >= length else { return frames }
                guard bytes[length - 2] == 0xCC && bytes[length - 1] == 0xDD else {
                    bytes.removeFirst()
                    continue
                }
                frames.append(Data(bytes.prefix(length)))
                bytes.removeFirst(length)
            }
        }
        return frames
    }

    private enum FrameLength {
        case incomplete
        case invalid
        case complete(Int)
    }

    private func frameLength() -> FrameLength {
        let command = bytes[2]
        // Older status replies omit brightness and are 12 bytes long.
        if command == 0x00 { return hasTrailer(at: 10) ? .complete(12) : .complete(13) }
        guard bytes.count >= 6 else { return .incomplete }
        let status = bytes[3]
        if status != 0 { return .complete(6) }

        switch command {
        case 0x87:
            guard bytes.count >= 9 else { return .incomplete }
            let descriptionLengthIndex = 8 + Int(bytes[7])
            guard descriptionLengthIndex < maximumFrameLength - 2 else { return .invalid }
            guard bytes.count > descriptionLengthIndex else { return .incomplete }
            let length = descriptionLengthIndex + 1 + Int(bytes[descriptionLengthIndex]) + 2
            return length <= maximumFrameLength ? .complete(length) : .invalid
        case 0x95:
            return hasTrailer(at: 4) ? .complete(6) : .complete(8)
        case 0x96:
            return hasTrailer(at: 4) ? .complete(6) : .complete(7)
        case 0x97:
            if hasTrailer(at: 4) { return .complete(6) }
            guard bytes.count >= 6, bytes[5] == 2 else { return .invalid }
            var offset = 6
            for _ in 0..<2 {
                guard bytes.count >= offset + 2 else { return .incomplete }
                offset += 2 + Int(bytes[offset + 1])
                guard offset + 2 <= maximumFrameLength else { return .invalid }
                guard bytes.count >= offset else { return .incomplete }
            }
            return .complete(offset + 2)
        case 0x9F:
            for index in 4..<bytes.count {
                if bytes[index] == 0xCC {
                    guard index + 1 < bytes.count else { return .incomplete }
                    return bytes[index + 1] == 0xDD ? .complete(index + 2) : .invalid
                }
                if bytes[index] < 0x20 || bytes[index] > 0x7E { return .invalid }
            }
            return .incomplete
        default:
            return .invalid
        }
    }

    private func hasTrailer(at index: Int) -> Bool {
        bytes.count >= index + 2 && bytes[index] == 0xCC && bytes[index + 1] == 0xDD
    }
}
