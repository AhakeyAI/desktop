import Foundation
import CryptoKit

public struct FirmwareImageDescriptor: Equatable, Sendable {
    public let url: URL
    public let fileName: String
    public let byteCount: Int
    public let sha256: String
    public let isBundled: Bool

    public var formattedByteCount: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteCount))
    }
}

public enum FirmwareImageValidationError: LocalizedError, Equatable {
    case invalidExtension
    case unreadable
    case empty
    case tooLarge(maxBytes: Int)
    case invalidText
    case malformedRecord(line: Int)
    case invalidChecksum(line: Int)
    case unsupportedRecordType(line: Int, type: UInt8)
    case addressOutOfRange(line: Int, maximumExclusive: UInt64)
    case missingDataRecord
    case missingEOF

    public var errorDescription: String? {
        switch self {
        case .invalidExtension:
            return "请选择扩展名为 .hex 的 Intel HEX 固件。"
        case .unreadable:
            return "无法读取所选固件文件。"
        case .empty:
            return "所选固件文件为空。"
        case .tooLarge(let maxBytes):
            return "固件文件超过 \(maxBytes / 1024 / 1024) MB 安全上限。"
        case .invalidText:
            return "固件不是有效的 UTF-8 / ASCII Intel HEX 文本。"
        case .malformedRecord(let line):
            return "Intel HEX 第 \(line) 行格式不完整。"
        case .invalidChecksum(let line):
            return "Intel HEX 第 \(line) 行校验和错误。"
        case .unsupportedRecordType(let line, let type):
            return "Intel HEX 第 \(line) 行使用了不支持的记录类型 0x\(String(format: "%02X", type))。"
        case .addressOutOfRange(let line, let maximumExclusive):
            return "Intel HEX 第 \(line) 行超出 CH582 CodeFlash 地址范围（0x000000–0x\(String(format: "%06llX", maximumExclusive - 1))）。"
        case .missingDataRecord:
            return "Intel HEX 中没有可写入的数据记录。"
        case .missingEOF:
            return "Intel HEX 缺少 EOF 结束记录。"
        }
    }
}

public enum FirmwareImageValidator {
    public static let maximumFileSize = 16 * 1024 * 1024
    public static let ch582CodeFlashSize: UInt64 = 448 * 1024

    public static func validate(url: URL, isBundled: Bool = false) throws -> FirmwareImageDescriptor {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw FirmwareImageValidationError.unreadable
        }
        return try validate(data: data, sourceURL: url, isBundled: isBundled)
    }

    public static func validate(
        data: Data,
        sourceURL url: URL,
        isBundled: Bool = false
    ) throws -> FirmwareImageDescriptor {
        guard url.pathExtension.lowercased() == "hex" else {
            throw FirmwareImageValidationError.invalidExtension
        }
        guard !data.isEmpty else { throw FirmwareImageValidationError.empty }
        guard data.count <= maximumFileSize else {
            throw FirmwareImageValidationError.tooLarge(maxBytes: maximumFileSize)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw FirmwareImageValidationError.invalidText
        }

        var hasDataRecord = false
        var hasEOF = false
        var baseAddress: UInt64 = 0
        let lines = text.components(separatedBy: .newlines)

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard line.first == ":" else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }

            let payload = String(line.dropFirst())
            guard payload.count.isMultiple(of: 2), payload.count >= 10 else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }

            var bytes: [UInt8] = []
            bytes.reserveCapacity(payload.count / 2)
            var index = payload.startIndex
            while index < payload.endIndex {
                let next = payload.index(index, offsetBy: 2)
                guard let byte = UInt8(payload[index..<next], radix: 16) else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                bytes.append(byte)
                index = next
            }

            let dataLength = Int(bytes[0])
            guard bytes.count == dataLength + 5 else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }
            guard bytes.reduce(0, { ($0 + Int($1)) & 0xFF }) == 0 else {
                throw FirmwareImageValidationError.invalidChecksum(line: lineNumber)
            }
            guard !hasEOF else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }

            switch bytes[3] {
            case 0x00:
                let recordAddress = UInt64(bytes[1]) << 8 | UInt64(bytes[2])
                let startAddress = baseAddress + recordAddress
                let endAddress = startAddress + UInt64(dataLength)
                guard endAddress <= ch582CodeFlashSize else {
                    throw FirmwareImageValidationError.addressOutOfRange(
                        line: lineNumber,
                        maximumExclusive: ch582CodeFlashSize
                    )
                }
                hasDataRecord = hasDataRecord || dataLength > 0
            case 0x01:
                guard dataLength == 0, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                hasEOF = true
            case 0x02:
                guard dataLength == 2, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                baseAddress = (UInt64(bytes[4]) << 8 | UInt64(bytes[5])) << 4
            case 0x03:
                guard dataLength == 4, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
            case 0x04:
                guard dataLength == 2, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                baseAddress = (UInt64(bytes[4]) << 8 | UInt64(bytes[5])) << 16
            case 0x05:
                guard dataLength == 4, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
            default:
                throw FirmwareImageValidationError.unsupportedRecordType(
                    line: lineNumber,
                    type: bytes[3]
                )
            }
        }

        guard hasDataRecord else { throw FirmwareImageValidationError.missingDataRecord }
        guard hasEOF else { throw FirmwareImageValidationError.missingEOF }

        return FirmwareImageDescriptor(
            url: url,
            fileName: url.lastPathComponent,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            isBundled: isBundled
        )
    }
}
