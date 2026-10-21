import Foundation

/// A complete set of per-setting observations, not an atomic firmware snapshot.
public struct WS3LightCatalogSnapshot: Equatable {
    public let generation: UInt64
    public let lights: [WS3SingleLightSnapshot]

    public init?(generation: UInt64, lights: [WS3SingleLightSnapshot]) {
        guard lights.count == 36,
              lights.allSatisfy({ $0.generation == generation && $0.mode < 4 && $0.state < 9 }),
              Set(lights.map { Int($0.mode) * 9 + Int($0.state) }).count == 36 else { return nil }
        self.generation = generation
        self.lights = lights.sorted { Int($0.mode) * 9 + Int($0.state) < Int($1.mode) * 9 + Int($1.state) }
    }

    public func light(mode: UInt8, state: UInt8) -> WS3SingleLightSnapshot? {
        guard mode < 4, state < 9 else { return nil }
        return lights[Int(mode) * 9 + Int(state)]
    }

    public func replacing(_ value: WS3SingleLightSnapshot) -> Self? {
        guard value.generation == generation, value.mode < 4, value.state < 9 else { return nil }
        var updated = lights
        updated[Int(value.mode) * 9 + Int(value.state)] = value
        return Self(generation: generation, lights: updated)
    }
}

public enum WS3LightCatalogError: Error, LocalizedError, Equatable {
    case unverifiedConnection, invalidReply, unsupported, rejected(UInt8)
    public var errorDescription: String? {
        switch self {
        case .unverifiedConnection: return NSLocalizedString("请在当前连接重新读取完整显示信息。", comment: "")
        case .invalidReply: return NSLocalizedString("灯效总览回复不完整，未确认完整结果，请重新读取。", comment: "")
        case .unsupported: return NSLocalizedString("当前固件不支持完整灯效读回。", comment: "")
        case .rejected: return NSLocalizedString("键盘拒绝了灯效总览读取，请重新读取。", comment: "")
        }
    }
}

@MainActor
public enum ConfirmedWS3LightCatalog {
    public static func read(baseline: WS3DisplaySnapshot, generation: UInt64,
                            checkSession: () throws -> Void,
                            exchange: (Data) async throws -> Data) async throws -> WS3LightCatalogSnapshot {
        guard baseline.verifiesDisplaySettings(in: generation) else { throw WS3LightCatalogError.unverifiedConnection }
        var lights: [WS3SingleLightSnapshot] = []
        for mode: UInt8 in 0..<4 {
            for state: UInt8 in 0..<9 {
                try Task.checkCancellation(); try checkSession()
                let item = WS3DisplayItem.singleLight(mode: mode, state: state)
                let reply = try await exchange(item.request!)
                try Task.checkCancellation(); try checkSession()
                switch WS3DisplayValue.parse(reply, for: item) {
                case .singleLight(let effect):
                    lights.append(.init(generation: generation, mode: mode, state: state, effect: effect))
                case .unsupported: throw WS3LightCatalogError.unsupported
                case .rejected(let status): throw WS3LightCatalogError.rejected(status)
                default: throw WS3LightCatalogError.invalidReply
                }
            }
        }
        guard let catalog = WS3LightCatalogSnapshot(generation: generation, lights: lights) else {
            throw WS3LightCatalogError.invalidReply
        }
        return catalog
    }
}
