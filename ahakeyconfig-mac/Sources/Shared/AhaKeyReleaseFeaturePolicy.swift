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

/// 单一投影：UI 可见性、可写表面、resource package 资格。C-2 接线后只消费本类型。
public struct AhaKeyReleaseFeatureProjection: Equatable, Sendable {
    public let channel: AhaKeyReleaseChannel
    public let allowedWriteSurfaces: Set<AhaKeyWriteSurface>
    public let showsKeysAndLightEditor: Bool
    public let showsDefaultPictureEditor: Bool
    public let showsTaskPictureEditor: Bool
    public let allowsResourcePackage: Bool
    public let allowsBasicConfigurationWrite: Bool
    public let deferredOLEDMessage: String?

    public var showsOLEDInspector: Bool {
        showsDefaultPictureEditor || showsTaskPictureEditor
    }

    public func allows(_ surface: AhaKeyWriteSurface) -> Bool {
        allowedWriteSurfaces.contains(surface)
    }
}

/// 集中式发布功能策略。以发布通道与已协商的 `AhaKeyProtocolMode` 为输入，不复制 0x99 parser。
public struct AhaKeyReleaseFeaturePolicy: Equatable, Sendable {
    public static let v0_2 = AhaKeyReleaseFeaturePolicy(channel: .v0_2)
    /// 编译期当前发布列车。v0.2 客户端必须走该通道。
    public static let current = v0_2

    public let channel: AhaKeyReleaseChannel

    public init(channel: AhaKeyReleaseChannel) {
        self.channel = channel
    }

    /// 从已解析的 0x99 结果推导协议模式。
    /// nil / 畸形 / 截断帧不得猜成 `.current`；无固件主版本时 fail-closed 为 `.restrictedUnknown`。
    public static func resolvedProtocolMode(
        parsedCapabilities: AhaKeyFirmwareCapabilities?,
        firmwareMainVersion: Int? = nil,
        supportsLegacyTaskPictures: Bool = false
    ) -> AhaKeyProtocolMode {
        if let parsedCapabilities {
            return AhaKeyProtocolNegotiation.mode(forCapabilities: parsedCapabilities)
        }
        guard let firmwareMainVersion else {
            return .restrictedUnknown
        }
        return AhaKeyProtocolNegotiation.fallbackMode(
            firmwareMainVersion: firmwareMainVersion,
            supportsLegacyTaskPictures: supportsLegacyTaskPictures
        )
    }

    /// - Parameters:
    ///   - protocolMode: 已完成协商的终态；调用方不得把解析失败猜成 `.current`。
    ///   - capabilities: 矩阵输入。v0.2 不得用其升级 OLED/resource 资格，即使 caps14 解析为 current。
    public func projection(
        protocolMode: AhaKeyProtocolMode,
        capabilities _: AhaKeyFirmwareCapabilities? = nil
    ) -> AhaKeyReleaseFeatureProjection {
        switch channel {
        case .v0_2:
            return Self.v0_2Projection(protocolMode: protocolMode)
        }
    }

    /// v0.2：所有协议模式都关闭 default/task picture 与 resource package。
    /// 基础配置只留给明确识别的安全终态；negotiating / restrictedUnknown 不开放任何写入。
    private static func v0_2Projection(
        protocolMode: AhaKeyProtocolMode
    ) -> AhaKeyReleaseFeatureProjection {
        let allowsBasic: Bool
        switch protocolMode {
        case .legacy, .legacyBaseOnly, .current:
            allowsBasic = true
        case .negotiating, .restrictedUnknown:
            allowsBasic = false
        }

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
            deferredOLEDMessage: "需 0.3 固件"
        )
    }
}
