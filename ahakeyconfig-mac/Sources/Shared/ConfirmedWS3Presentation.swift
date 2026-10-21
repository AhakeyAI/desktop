import Foundation

public enum WS3PresentationError: String, Error, LocalizedError {
    case unavailable, busy, unsupported, connectionChanged, rejected, invalidReply, timedOut
    public var errorDescription: String? {
        switch self {
        case .unavailable: return NSLocalizedString("请先连接键盘并返回日常连接。", comment: "")
        case .busy: return NSLocalizedString("键盘正在处理请求，请稍后重试。", comment: "")
        case .unsupported: return NSLocalizedString("此固件尚未确认支持新的显示方式，未切换。", comment: "")
        case .connectionChanged: return NSLocalizedString("连接已变化，显示请求未确认，请重新读取并应用。", comment: "")
        case .rejected, .invalidReply: return NSLocalizedString("显示请求未确认；已发出的更改可能已生效，请重新读取并应用。", comment: "")
        case .timedOut: return NSLocalizedString("显示请求超时，已停止同步；请重新连接后再试。", comment: "")
        }
    }
}

/// Current-connection proof before any 0x98/99 writes. A shared catalog alone,
/// a generic 0x88 ACK, or cached metadata is never sufficient. No persistence.
@MainActor
public enum ConfirmedWS3Presentation {
    public static func activate(_ mode: WS3PresentationMode, generation: UInt64,
                                checkSession: () throws -> Void,
                                exchange: (Data) async throws -> Data) async throws {
        func checked(_ request: Data) async throws -> Data {
            try Task.checkCancellation(); try checkSession()
            let reply = try await exchange(request)
            try Task.checkCancellation(); try checkSession()
            return reply
        }
        let catalog = try await checked(Data([0xAA, 0xBB, 0x9F, 0xCC, 0xDD]))
        guard FirmwareCapabilityProfile.catalogResponse(catalog).identity == .knownWS2Catalog else {
            throw WS3PresentationError.unsupported
        }
        func read(_ item: WS3DisplayItem) async throws -> WS3DisplayValue {
            let reply = try await checked(item.request!)
            guard let value = WS3DisplayValue.parse(reply, for: item) else { throw WS3PresentationError.invalidReply }
            if case .unsupported = value { throw WS3PresentationError.unsupported }
            if case .rejected = value { throw WS3PresentationError.rejected }
            return value
        }
        guard case .brightness(let brightness) = try await read(.brightness), (1...100).contains(brightness) else {
            throw WS3PresentationError.unsupported
        }
        var resources: [WS3ResourceReadback] = []
        for id: UInt8 in 0..<19 {
            let basic = try await read(.resourceBasic(id))
            let integrity = try await read(.resourceIntegrity(id))
            guard let value = WS3ResourceReadback(id: id, basic: basic, integrity: integrity) else {
                throw WS3PresentationError.invalidReply
            }
            resources.append(value)
        }
        guard WS3DisplaySnapshot(generation: generation, brightness: brightness, resources: resources)
            .verifiesDisplaySettings(in: generation) else { throw WS3PresentationError.unsupported }
        func send(_ command: WS3PresentationCommand) async throws {
            let reply = try await checked(command.request!)
            switch WS3PresentationAcknowledgement.parse(reply, for: command) {
            case .received: break // A receipt is not proof of visible presentation.
            case .rejected: throw WS3PresentationError.rejected
            case nil: throw WS3PresentationError.invalidReply
            }
        }
        try await send(.setMode(mode))
        // A previously selected MULTI mode survives disconnects. Establish an
        // empty boundary even when firmware considers this set idempotent.
        if mode == .multi { try await send(.multi(WS3TaskSnapshot(slots: [nil, nil, nil, nil])!)) }
    }
}
