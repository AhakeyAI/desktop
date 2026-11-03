import Foundation

/// Projects a framed desktop snapshot without retaining its conversation body.
/// Wire length is bounded by the UInt32 protocol and the caller's IO deadline;
/// retained JSON is capped independently, regardless of conversation length.
enum CodexDesktopSettingsFrame {
    static let chunkSize = 65_536
    static let retainedLimit = 1_048_576

    private indirect enum Selection {
        case value
        case object([String: Selection])
    }

    static func read(length: UInt32, readChunk: @escaping (Int) throws -> Data) throws -> [String: Any] {
        let permission: Selection = .object([
            "approvalPolicy": .value, "permissions": .value, "sandboxPolicy": .value,
            "activePermissionProfile": .object(["id": .value])
        ])
        let selection: [String: Selection] = [
            "type": .value, "method": .value, "version": .value,
            "sourceClientId": .value, "requestId": .value,
            "params": .object([
                "hostId": .value, "conversationId": .value,
                "change": .object([
                    "type": .value,
                    "conversationState": .object(["id": .value, "latestThreadSettings": permission])
                ])
            ])
        ]
        var reader = Reader(remaining: Int(length), readChunk: readChunk)
        return try reader.frame(selection)
    }

    private struct Reader {
        let readChunk: (Int) throws -> Data
        var remaining: Int
        var buffer: [UInt8] = []
        var index = 0
        var retainedBytes = 0
        var capture: Data?
        var keyCapture: Data?
        var oversizedKey = false

        init(remaining: Int, readChunk: @escaping (Int) throws -> Data) {
            self.remaining = remaining; self.readChunk = readChunk
        }

        mutating func frame(_ selection: [String: Selection]) throws -> [String: Any] {
            guard remaining > 0 else { throw invalid }
            try whitespace()
            let result = try object(selection, depth: 0)
            try whitespace()
            guard try peek() == nil else { throw invalid }
            return result
        }

        private var invalid: CodexDesktopSessionBridge.BridgeError { .invalidFrame }

        mutating func peek() throws -> UInt8? {
            if index == buffer.count, remaining > 0 {
                let count = min(remaining, CodexDesktopSettingsFrame.chunkSize)
                let data = try readChunk(count)
                guard data.count == count else { throw invalid }
                buffer = Array(data); index = 0; remaining -= count
            }
            return index < buffer.count ? buffer[index] : nil
        }

        mutating func emit(_ byte: UInt8) throws {
            if capture != nil {
                guard retainedBytes < CodexDesktopSettingsFrame.retainedLimit else { throw invalid }
                capture!.append(byte); retainedBytes += 1
            }
            if keyCapture != nil {
                if keyCapture!.count < 4096 { keyCapture!.append(byte) }
                else { keyCapture = nil; oversizedKey = true }
            }
        }

        mutating func take() throws -> UInt8 {
            guard let value = try peek() else { throw invalid }
            index += 1; try emit(value); return value
        }

        mutating func expect(_ byte: UInt8) throws {
            guard try take() == byte else { throw invalid }
        }

        mutating func whitespace() throws {
            while let value = try peek(), [UInt8(9), 10, 13, 32].contains(value) { _ = try take() }
        }

        mutating func object(_ selection: [String: Selection], depth: Int) throws -> [String: Any] {
            guard depth < 512 else { throw invalid }
            try expect(123); try whitespace()
            var result: [String: Any] = [:]
            if try peek() == 125 { _ = try take(); return result }
            while true {
                let key = try string(key: true)
                try whitespace(); try expect(58); try whitespace()
                if let key, let selected = selection[key] {
                    if case .object(let child) = selected, try peek() == 123 {
                        result[key] = try object(child, depth: depth + 1)
                    } else { result[key] = try capturedValue(depth: depth + 1) }
                } else { try skipValue(depth: depth + 1) }
                try whitespace()
                let separator = try take()
                if separator == 125 { return result }
                guard separator == 44 else { throw invalid }
                try whitespace()
            }
        }

        mutating func capturedValue(depth: Int) throws -> Any {
            capture = Data()
            defer { capture = nil }
            try skipValue(depth: depth)
            do { return try JSONSerialization.jsonObject(with: capture!, options: [.fragmentsAllowed]) }
            catch { throw invalid }
        }

        mutating func skipValue(depth: Int) throws {
            guard depth < 512, let value = try peek() else { throw invalid }
            switch value {
            case 34: _ = try string()
            case 123:
                try expect(123); try whitespace()
                if try peek() == 125 { _ = try take(); return }
                while true {
                    _ = try string(); try whitespace(); try expect(58); try whitespace()
                    try skipValue(depth: depth + 1); try whitespace()
                    let separator = try take()
                    if separator == 125 { return }
                    guard separator == 44 else { throw invalid }; try whitespace()
                }
            case 91:
                try expect(91); try whitespace()
                if try peek() == 93 { _ = try take(); return }
                while true {
                    try skipValue(depth: depth + 1); try whitespace()
                    let separator = try take()
                    if separator == 93 { return }
                    guard separator == 44 else { throw invalid }; try whitespace()
                }
            case 116: for byte in "true".utf8 { try expect(byte) }
            case 102: for byte in "false".utf8 { try expect(byte) }
            case 110: for byte in "null".utf8 { try expect(byte) }
            case 45, 48...57: try number()
            default: throw invalid
            }
        }

        mutating func number() throws {
            if try peek() == 45 { _ = try take() }
            if try peek() == 48 { _ = try take() }
            else {
                guard let value = try peek(), (49...57).contains(value) else { throw invalid }
                try digits()
            }
            if try peek() == 46 { _ = try take(); try digits() }
            if let value = try peek(), value == 101 || value == 69 {
                _ = try take()
                if let sign = try peek(), sign == 43 || sign == 45 { _ = try take() }
                try digits()
            }
        }

        mutating func digits() throws {
            guard let value = try peek(), (48...57).contains(value) else { throw invalid }
            repeat { _ = try take() } while try peek().map({ (48...57).contains($0) }) == true
        }

        mutating func hex4() throws -> UInt16 {
            var value: UInt16 = 0
            for _ in 0..<4 {
                let byte = try take(), digit: UInt8
                switch byte {
                case 48...57: digit = byte - 48
                case 65...70: digit = byte - 55
                case 97...102: digit = byte - 87
                default: throw invalid
                }
                value = value << 4 | UInt16(digit)
            }
            return value
        }

        mutating func string(key: Bool = false) throws -> String? {
            keyCapture = key ? Data() : nil; oversizedKey = false
            defer { keyCapture = nil }
            try expect(34)
            var continuation = 0, lower: UInt8 = 128, upper: UInt8 = 191
            while let value = try peek() {
                // Most conversation bodies are long ASCII spans. Skip them in
                // the fixed buffer rather than allocating or decoding strings.
                if continuation == 0, value >= 32, value < 128, value != 34, value != 92 {
                    let start = index
                    while index < buffer.count {
                        let byte = buffer[index]
                        if byte < 32 || byte >= 128 || byte == 34 || byte == 92 { break }
                        index += 1
                    }
                    let span = buffer[start..<index]
                    if capture != nil {
                        guard span.count <= CodexDesktopSettingsFrame.retainedLimit - retainedBytes else { throw invalid }
                        capture!.append(contentsOf: span); retainedBytes += span.count
                    }
                    if keyCapture != nil {
                        if span.count <= 4096 - keyCapture!.count { keyCapture!.append(contentsOf: span) }
                        else { keyCapture = nil; oversizedKey = true }
                    }
                    continue
                }
                let byte = try take()
                if continuation > 0 {
                    guard (lower...upper).contains(byte) else { throw invalid }
                    continuation -= 1; lower = 128; upper = 191; continue
                }
                if byte == 34 {
                    guard key, !oversizedKey, let data = keyCapture else { return nil }
                    do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String }
                    catch { throw invalid }
                }
                if byte == 92 {
                    let escaped = try take()
                    if escaped == 117 {
                        let scalar = try hex4()
                        if (0xD800...0xDBFF).contains(scalar) {
                            try expect(92); try expect(117)
                            guard (0xDC00...0xDFFF).contains(try hex4()) else { throw invalid }
                        } else if (0xDC00...0xDFFF).contains(scalar) { throw invalid }
                    } else if ![UInt8(34), 92, 47, 98, 102, 110, 114, 116].contains(escaped) { throw invalid }
                    continue
                }
                switch byte {
                case 194...223: continuation = 1
                case 224: continuation = 2; lower = 160
                case 225...236, 238...239: continuation = 2
                case 237: continuation = 2; upper = 159
                case 240: continuation = 3; lower = 144
                case 241...243: continuation = 3
                case 244: continuation = 3; upper = 143
                default: throw invalid
                }
            }
            throw invalid
        }
    }
}
