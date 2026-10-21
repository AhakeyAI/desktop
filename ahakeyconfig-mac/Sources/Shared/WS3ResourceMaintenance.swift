import Foundation

public enum WS3ResourceMaintenanceError: Error, LocalizedError, Equatable {
    case unverifiedConnection, conflict, busy, invalidReadback, rejected(UInt8), verificationMismatch
    public var errorDescription: String? {
        switch self {
        case .unverifiedConnection: return NSLocalizedString("请在当前连接重新读取完整显示信息。", comment: "")
        case .conflict: return NSLocalizedString("此位置的素材已变化，未执行恢复；请重新读取。", comment: "")
        case .busy: return NSLocalizedString("此位置仍在上传中，不能恢复默认显示。", comment: "")
        case .invalidReadback: return NSLocalizedString("素材读回无效，当前状态未确认。", comment: "")
        case .rejected: return NSLocalizedString("键盘拒绝恢复默认显示，请重新读取后再试。", comment: "")
        case .verificationMismatch: return NSLocalizedString("恢复后的素材状态不一致，尚未确认成功；请重新连接并读取。", comment: "")
        }
    }
}

/// Comparison of prepared host bytes with reported metadata, not Flash bytes.
public enum WS3ResourceMetadataComparison: Equatable {
    case matches, different, noValidCustomResource
    public init(payload: WS3ResourcePayload, resource: WS3ResourceReadback) {
        if payload.entryID != resource.id { self = .different }
        else if !resource.reportsValidUserResource { self = .noValidCustomResource }
        else if payload.frameCount == resource.frames && UInt32(payload.bytes.count) == resource.payloadBytes && payload.crc32 == resource.crc32 { self = .matches }
        else { self = .different }
    }
}

public enum WS3ResourceRestoreCommand {
    public static func request(entry: UInt8) -> Data? {
        guard entry < 19 else { return nil }
        return Data([0xAA, 0xBB, 0x8D, entry, 0xCC, 0xDD])
    }
    public static func validRequest(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        return bytes.count == 6 && request(entry: bytes[3]) == Data(bytes)
    }
    public static func reportsDefault(_ resource: WS3ResourceReadback) -> Bool {
        !resource.userValid && resource.writeState == .empty && resource.frames == 0 && resource.payloadBytes == 0 && resource.crc32 == 0
    }
}

/// CP2 8D clears one persistent metadata entry. It does not erase Flash bytes,
/// abort an upload, restore an old image, or reset keys/voice/other resources.
@MainActor
public enum ConfirmedWS3ResourceMaintenance {
    public static func read(entry: UInt8, baseline: WS3DisplaySnapshot, generation: UInt64,
                            checkSession: () throws -> Void,
                            exchange: (Data) async throws -> Data) async throws -> WS3ResourceReadback {
        _ = try validate(entry: entry, baseline: baseline, generation: generation)
        return try await readConfirmed(entry: entry, checkSession: checkSession, exchange: exchange)
    }

    public static func restoreDefault(entry: UInt8, baseline: WS3DisplaySnapshot, generation: UInt64,
                                      checkSession: () throws -> Void,
                                      exchange: (Data) async throws -> Data) async throws -> WS3ResourceReadback {
        let previous = try validate(entry: entry, baseline: baseline, generation: generation)
        let current = try await readConfirmed(entry: entry, checkSession: checkSession, exchange: exchange)
        guard current == previous else { throw WS3ResourceMaintenanceError.conflict }
        // A fresh empty marker is an idempotent no-write result.
        if WS3ResourceRestoreCommand.reportsDefault(current) { return current }
        guard current.writeState != .writing else { throw WS3ResourceMaintenanceError.busy }
        let reply = [UInt8](try await checked(WS3ResourceRestoreCommand.request(entry: entry)!, checkSession: checkSession, exchange: exchange))
        guard reply.count == 6, reply[0...2] == [0xAA, 0xBB, 0x8D], reply.suffix(2) == [0xCC, 0xDD] else {
            throw WS3ResourceMaintenanceError.invalidReadback
        }
        guard reply[3] == 0 else { throw WS3ResourceMaintenanceError.rejected(reply[3]) }
        let actual = try await readConfirmed(entry: entry, checkSession: checkSession, exchange: exchange)
        guard WS3ResourceRestoreCommand.reportsDefault(actual) else { throw WS3ResourceMaintenanceError.verificationMismatch }
        return actual
    }

    private static func validate(entry: UInt8, baseline: WS3DisplaySnapshot, generation: UInt64) throws -> WS3ResourceReadback {
        guard entry < 19, baseline.verifiesDisplaySettings(in: generation),
              let resource = baseline.resources.first(where: { $0.id == entry }) else {
            throw WS3ResourceMaintenanceError.unverifiedConnection
        }
        return resource
    }
    private static func checked(_ request: Data, checkSession: () throws -> Void,
                                exchange: (Data) async throws -> Data) async throws -> Data {
        try Task.checkCancellation(); try checkSession()
        let reply = try await exchange(request)
        try Task.checkCancellation(); try checkSession()
        return reply
    }
    private static func readConfirmed(entry: UInt8, checkSession: () throws -> Void,
                                      exchange: (Data) async throws -> Data) async throws -> WS3ResourceReadback {
        let basic = WS3DisplayItem.resourceBasic(entry), integrity = WS3DisplayItem.resourceIntegrity(entry)
        let first = try await checked(basic.request!, checkSession: checkSession, exchange: exchange)
        let second = try await checked(integrity.request!, checkSession: checkSession, exchange: exchange)
        guard let resource = WS3ResourceReadback(id: entry,
            basic: WS3DisplayValue.parse(first, for: basic) ?? .unsupported,
            integrity: WS3DisplayValue.parse(second, for: integrity) ?? .unsupported) else {
            throw WS3ResourceMaintenanceError.invalidReadback
        }
        return resource
    }
}
