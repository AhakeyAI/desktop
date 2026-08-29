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

/// 发布功能策略的唯一合法输入。协商来源与能力绑定，调用方不能把独立 mode + capabilities 拼起来绕过 resolver。
public enum AhaKeyReleaseNegotiationState: Equatable, Sendable {
    /// 已连接、0x99 尚未完成。
    case negotiating
    /// 0x99 无应答。仅此路径可产生 `.legacy` / `.legacyBaseOnly`。
    case noResponse(firmwareMainVersion: Int?, supportsLegacyTaskPictures: Bool)
    /// 收到畸形/截断 0x99。一律 `.restrictedUnknown`，即使固件 1.x。
    case malformedResponse
    /// 已解析的能力帧。协议模式由现有 negotiation 推导，不得另传 mode。
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

    /// 测试夹具：开放图片写入面。生产路径必须用 `AhaKeyReleaseFeaturePolicy.current.projection`。
    public static let picturesUnrestrictedForTests = AhaKeyReleaseFeatureProjection(
        channel: .v0_2,
        allowedWriteSurfaces: [.keysAndLight, .defaultPictures, .taskPictures],
        showsKeysAndLightEditor: true,
        showsDefaultPictureEditor: true,
        showsTaskPictureEditor: true,
        allowsResourcePackage: true,
        allowsBasicConfigurationWrite: true,
        deferredOLEDReason: nil
    )

    public var showsOLEDInspector: Bool {
        showsDefaultPictureEditor || showsTaskPictureEditor
    }

    public func allows(_ surface: AhaKeyWriteSurface) -> Bool {
        allowedWriteSurfaces.contains(surface)
    }

    /// 默认图或任务图任一写入面开放即视为允许图片步骤（0x95/0x97/资源包）。
    public var allowsPictureWrites: Bool {
        allows(.defaultPictures) || allows(.taskPictures)
    }
}

/// 集中式发布功能策略。以发布通道与单一协商状态为输入，不复制 0x99 parser。
public struct AhaKeyReleaseFeaturePolicy: Equatable, Sendable {
    public static let v0_2 = AhaKeyReleaseFeaturePolicy(channel: .v0_2)
    /// 编译期当前发布列车。v0.2 客户端必须走该通道。
    public static let current = v0_2

    public let channel: AhaKeyReleaseChannel

    public init(channel: AhaKeyReleaseChannel) {
        self.channel = channel
    }

    /// 从协商状态推导协议模式。畸形/截断应答一律 `.restrictedUnknown`，不得按固件 1.x 回退 legacy。
    public static func resolvedProtocolMode(
        _ state: AhaKeyReleaseNegotiationState
    ) -> AhaKeyProtocolMode {
        switch state {
        case .negotiating:
            return .negotiating
        case .malformedResponse:
            return .restrictedUnknown
        case .parsed(let capabilities):
            return AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities)
        case .noResponse(let firmwareMainVersion, let supportsLegacyTaskPictures):
            guard let firmwareMainVersion else {
                return .restrictedUnknown
            }
            return AhaKeyProtocolNegotiation.fallbackMode(
                firmwareMainVersion: firmwareMainVersion,
                supportsLegacyTaskPictures: supportsLegacyTaskPictures
            )
        }
    }

    public func projection(
        _ state: AhaKeyReleaseNegotiationState
    ) -> AhaKeyReleaseFeatureProjection {
        switch channel {
        case .v0_2:
            return Self.v0_2Projection(state)
        }
    }

    /// v0.2：所有协商状态都关闭 default/task picture 与 resource package。
    /// 基础配置只留给带协商来源的安全终态。
    private static func v0_2Projection(
        _ state: AhaKeyReleaseNegotiationState
    ) -> AhaKeyReleaseFeatureProjection {
        let allowsBasic = allowsBasicConfiguration(state)

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

    /// `.current` 只来自能协商为 current 的已解析能力帧；`.legacy` / `.legacyBaseOnly` 只来自无应答回退。
    /// negotiating、malformed、未知固件无应答都不开放写入。
    private static func allowsBasicConfiguration(
        _ state: AhaKeyReleaseNegotiationState
    ) -> Bool {
        switch state {
        case .negotiating, .malformedResponse:
            return false
        case .noResponse:
            switch resolvedProtocolMode(state) {
            case .legacy, .legacyBaseOnly:
                return true
            case .negotiating, .current, .restrictedUnknown:
                return false
            }
        case .parsed:
            return resolvedProtocolMode(state) == .current
        }
    }
}
