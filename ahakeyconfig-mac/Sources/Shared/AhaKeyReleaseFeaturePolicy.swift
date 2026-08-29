import Foundation

/// 发布列车功能面。C-1 只冻结 v0.2；更高版本由后续卡扩展。
public enum AhaKeyReleaseChannel: Equatable, Sendable {
    /// 当前量产固件兼容客户端：只开放基础键位/灯效。
    case v0_2
}

/// 可独立授权的写入面。键位/灯效必须与图片面分离。
public enum AhaKeyWriteSurface: Equatable, Hashable, Sendable {
    case keysAndLight
    case defaultPictures
    case taskPictures
}

/// OLED 延后原因。展示文案由 UI 层本地化，Shared 不嵌入用户可见字符串。
public enum AhaKeyDeferredOLEDReason: Equatable, Sendable {
    case requiresFirmwareV0_3
}

/// 0x99 协商输入。必须把“无应答”和“收到畸形/截断应答”分开，避免 1.x 回退成可写 legacy。
public enum AhaKeyCapabilityNegotiationResult: Equatable {
    case noResponse
    case malformedResponse
    case parsed(AhaKeyFirmwareCapabilities)
}

/// 单一投影：UI 可见性、可写表面、resource package 资格。C-2 接线后只消费本类型。
public struct AhaKeyReleaseFeatureProjection: Equatable, Sendable {
    public let channel: AhaKeyReleaseChannel
    public let allowedWriteSurfaces: Set<AhaKeyWriteSurface>
    public let showsKeysAndLightEditor: Bool
    public let showsDefaultPictureEditor: Bool
    public let showsTaskPictureEditor: Bool
    public let allowsResourcePackage: Bool
    public let allowsBasicConfigurationWrite: Bool
    public let deferredOLEDReason: AhaKeyDeferredOLEDReason?

    public var showsOLEDInspector: Bool {
        showsDefaultPictureEditor || showsTaskPictureEditor
    }

    public func allows(_ surface: AhaKeyWriteSurface) -> Bool {
        allowedWriteSurfaces.contains(surface)
    }
}

/// 集中式发布功能策略。以发布通道与已协商的 `AhaKeyProtocolMode`/能力结果为输入，不复制 0x99 parser。
public struct AhaKeyReleaseFeaturePolicy: Equatable, Sendable {
    public static let v0_2 = AhaKeyReleaseFeaturePolicy(channel: .v0_2)
    /// 编译期当前发布列车。v0.2 客户端必须走该通道。
    public static let current = v0_2

    public let channel: AhaKeyReleaseChannel

    public init(channel: AhaKeyReleaseChannel) {
        self.channel = channel
    }

    /// 从协商结果推导协议模式。畸形/截断应答一律 `.restrictedUnknown`，不得按固件 1.x 回退 legacy。
    public static func resolvedProtocolMode(
        _ result: AhaKeyCapabilityNegotiationResult,
        firmwareMainVersion: Int? = nil,
        supportsLegacyTaskPictures: Bool = false
    ) -> AhaKeyProtocolMode {
        switch result {
        case .malformedResponse:
            return .restrictedUnknown
        case .parsed(let capabilities):
            return AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities)
        case .noResponse:
            guard let firmwareMainVersion else {
                return .restrictedUnknown
            }
            return AhaKeyProtocolNegotiation.fallbackMode(
                firmwareMainVersion: firmwareMainVersion,
                supportsLegacyTaskPictures: supportsLegacyTaskPictures
            )
        }
    }

    /// - Parameters:
    ///   - protocolMode: 已完成协商的终态。
    ///   - capabilities: 必须与 `protocolMode` 一致；矛盾或把 nil 猜成 current 时 fail-closed。
    public func projection(
        protocolMode: AhaKeyProtocolMode,
        capabilities: AhaKeyFirmwareCapabilities?
    ) -> AhaKeyReleaseFeatureProjection {
        switch channel {
        case .v0_2:
            return Self.v0_2Projection(protocolMode: protocolMode, capabilities: capabilities)
        }
    }

    /// v0.2：所有协议模式都关闭 default/task picture 与 resource package。
    /// 基础配置只留给与能力结果一致的安全终态。
    private static func v0_2Projection(
        protocolMode: AhaKeyProtocolMode,
        capabilities: AhaKeyFirmwareCapabilities?
    ) -> AhaKeyReleaseFeatureProjection {
        let allowsBasic = allowsBasicConfiguration(
            protocolMode: protocolMode,
            capabilities: capabilities
        )

        var surfaces: Set<AhaKeyWriteSurface> = []
        if allowsBasic {
            surfaces.insert(.keysAndLight)
        }

        return AhaKeyReleaseFeatureProjection(
            channel: .v0_2,
            allowedWriteSurfaces: surfaces,
            showsKeysAndLightEditor: allowsBasic,
            showsDefaultPictureEditor: false,
            showsTaskPictureEditor: false,
            allowsResourcePackage: false,
            allowsBasicConfigurationWrite: allowsBasic,
            deferredOLEDReason: .requiresFirmwareV0_3
        )
    }

    /// `.current` 必须带能协商为 current 的能力帧；`.legacy` / `.legacyBaseOnly` 只接受无应答（nil caps）。
    /// 模式与能力矛盾、negotiating、restrictedUnknown 都不开放写入。
    private static func allowsBasicConfiguration(
        protocolMode: AhaKeyProtocolMode,
        capabilities: AhaKeyFirmwareCapabilities?
    ) -> Bool {
        switch protocolMode {
        case .negotiating, .restrictedUnknown:
            return false
        case .current:
            guard let capabilities else { return false }
            return AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities) == .current
        case .legacy, .legacyBaseOnly:
            return capabilities == nil
        }
    }
}
