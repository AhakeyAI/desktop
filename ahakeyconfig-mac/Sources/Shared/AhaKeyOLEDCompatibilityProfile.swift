import Foundation

/// v0.3 OLED 兼容剖面。输入只能是已验证的 capability / 协议事实，禁止用固件版本字符串猜测。
///
/// 四态互斥：
/// - `legacyStandard`：无 `0x99`、固件 1.x、且 0x94 证实任务图（GitHub Standard）
/// - `rhinoDualSet`：已解析 protocol v3 + 双套（Gitee/Local Rhino）；session 仅当 flags 明确广告
/// - `currentSessionCapable`：已解析 protocol v3 且明确广告 session 上传
/// - `unsupported`：协商中、畸形/短帧、未知组合——写入前 fail-closed
public enum AhaKeyOLEDCompatibilityProfile: Equatable, Sendable {
    case legacyStandard
    case rhinoDualSet(sessionUploadAdvertised: Bool)
    case currentSessionCapable
    case unsupported

    /// 该剖面对图片写入允许的物理 opcode。未列出的 Rhino/current 命令视为禁止。
    public struct PictureOpcodePolicy: Equatable, Sendable {
        public let allowsPrepareWrite: Bool
        public let allowsSessionPrepare: Bool
        public let allowsSessionAbort: Bool
        public let allowsBindLegacyTaskPicture: Bool
        public let allowsBindDefaultPicture: Bool
        public let allowsBindTaskPicture: Bool
        public let allowsSetActiveSet: Bool
        public let allowsFinishTaskPicture: Bool

        public static let none = PictureOpcodePolicy(
            allowsPrepareWrite: false,
            allowsSessionPrepare: false,
            allowsSessionAbort: false,
            allowsBindLegacyTaskPicture: false,
            allowsBindDefaultPicture: false,
            allowsBindTaskPicture: false,
            allowsSetActiveSet: false,
            allowsFinishTaskPicture: false
        )
    }

    public var allowsConfigurationPlan: Bool {
        switch self {
        case .legacyStandard, .rhinoDualSet, .currentSessionCapable:
            return true
        case .unsupported:
            return false
        }
    }

    public var pictureOpcodes: PictureOpcodePolicy {
        switch self {
        case .legacyStandard:
            return PictureOpcodePolicy(
                allowsPrepareWrite: true,
                allowsSessionPrepare: false,
                allowsSessionAbort: false,
                allowsBindLegacyTaskPicture: true,
                allowsBindDefaultPicture: true,
                allowsBindTaskPicture: false,
                allowsSetActiveSet: false,
                allowsFinishTaskPicture: false
            )
        case .rhinoDualSet(let sessionUploadAdvertised):
            return PictureOpcodePolicy(
                allowsPrepareWrite: true,
                allowsSessionPrepare: sessionUploadAdvertised,
                allowsSessionAbort: sessionUploadAdvertised,
                allowsBindLegacyTaskPicture: false,
                allowsBindDefaultPicture: false,
                allowsBindTaskPicture: true,
                allowsSetActiveSet: true,
                allowsFinishTaskPicture: false
            )
        case .currentSessionCapable:
            return PictureOpcodePolicy(
                allowsPrepareWrite: false,
                allowsSessionPrepare: true,
                allowsSessionAbort: true,
                allowsBindLegacyTaskPicture: false,
                allowsBindDefaultPicture: false,
                allowsBindTaskPicture: true,
                allowsSetActiveSet: true,
                allowsFinishTaskPicture: false
            )
        case .unsupported:
            return .none
        }
    }

    /// 密封协商事实入口。畸形/截断 0x99 不得按固件 1.x 回退 Standard。
    public static func resolve(_ state: AhaKeyReleaseNegotiationState) -> AhaKeyOLEDCompatibilityProfile {
        switch state {
        case .negotiating, .malformedResponse:
            return .unsupported
        case .noResponse(let firmwareMainVersion, let supportsLegacyTaskPictures):
            guard firmwareMainVersion == 1, supportsLegacyTaskPictures else {
                return .unsupported
            }
            return .legacyStandard
        case .parsed(let capabilities):
            return resolveParsed(capabilities)
        }
    }

    /// planner/mapper 兼容入口。`protocolMode` 必须与能力事实一致：`.legacy` 不得携带 v3 0x99 帧。
    public static func resolve(
        protocolMode: AhaKeyProtocolMode,
        capabilities: AhaKeyFirmwareCapabilities?
    ) -> AhaKeyOLEDCompatibilityProfile {
        switch protocolMode {
        case .negotiating, .restrictedUnknown, .legacyBaseOnly:
            return .unsupported
        case .legacy:
            if let capabilities, capabilities.protocolVersion == 3 {
                return .unsupported
            }
            return .legacyStandard
        case .current:
            guard let capabilities else { return .unsupported }
            return resolveParsed(capabilities)
        }
    }

    /// protocol v3 已解析帧：Rhino = 双套（setCount≥2）；current = 明确广告 session 且非 Rhino 双套。
    /// 缺少双套且未广告 session 的 v3 帧不得猜测。
    public static func resolveParsed(
        _ capabilities: AhaKeyFirmwareCapabilities
    ) -> AhaKeyOLEDCompatibilityProfile {
        guard capabilities.protocolVersion == 3,
              capabilities.modeCount > 0,
              capabilities.setCount > 0,
              capabilities.stateCount > 0,
              capabilities.userSlotLimit > 0 else {
            return .unsupported
        }
        let dualSet = capabilities.setCount >= 2
        let session = capabilities.supportsSessionUpload
        if dualSet {
            return .rhinoDualSet(sessionUploadAdvertised: session)
        }
        if session {
            return .currentSessionCapable
        }
        return .unsupported
    }
}
