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

/// 密封生产兼容事实：只能从协商状态构造，禁止把 protocolMode / capabilities / profile 拼起来。
public struct AhaKeyOLEDCompatibilityContext: Equatable, Sendable {
    public let negotiation: AhaKeyReleaseNegotiationState
    public let profile: AhaKeyOLEDCompatibilityProfile

    /// GitHub Standard 1.x 用户槽：总槽约 74、出厂保留 10。这是已登记固件族的布局事实，不是伪 0x99 帧。
    public static let standardUserSlotLimit = 64
    public static let standardModeCount = 4
    public static let standardSetCount = 1
    public static let standardStateCount = 4

    public struct Layout: Equatable, Sendable {
        public let modeCount: Int
        public let setCount: Int
        public let stateCount: Int
        public let userSlotLimit: Int
    }

    public static func make(_ negotiation: AhaKeyReleaseNegotiationState) -> AhaKeyOLEDCompatibilityContext {
        AhaKeyOLEDCompatibilityContext(
            negotiation: negotiation,
            profile: AhaKeyOLEDCompatibilityProfile.resolve(negotiation)
        )
    }

    /// 已解析的真 0x99 帧。不得用于伪造 v1 Standard。
    public static func parsed(_ capabilities: AhaKeyFirmwareCapabilities) -> AhaKeyOLEDCompatibilityContext {
        make(.parsed(capabilities))
    }

    /// 真 no-0x99 + 固件 1.x + 0x94 实探通过。不是伪 capability 帧。
    public static let standard = AhaKeyOLEDCompatibilityContext.make(
        .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: true)
    )

    public var protocolMode: AhaKeyProtocolMode {
        switch negotiation {
        case .negotiating:
            return .negotiating
        case .malformedResponse:
            return .restrictedUnknown
        case .noResponse(let firmwareMainVersion, let supportsLegacyTaskPictures):
            guard let firmwareMainVersion else { return .restrictedUnknown }
            return AhaKeyProtocolNegotiation.fallbackMode(
                firmwareMainVersion: firmwareMainVersion,
                supportsLegacyTaskPictures: supportsLegacyTaskPictures
            )
        case .parsed(let capabilities):
            return AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities)
        }
    }

    /// 仅 `.parsed` 携带真 0x99 帧。Standard 不得合成 v1 capability。
    public var capabilities: AhaKeyFirmwareCapabilities? {
        if case .parsed(let capabilities) = negotiation { return capabilities }
        return nil
    }

    public var layout: Layout {
        switch profile {
        case .legacyStandard:
            return Layout(
                modeCount: Self.standardModeCount,
                setCount: Self.standardSetCount,
                stateCount: Self.standardStateCount,
                userSlotLimit: Self.standardUserSlotLimit
            )
        case .rhinoDualSet, .currentSessionCapable:
            if let capabilities {
                return Layout(
                    modeCount: capabilities.modeCount,
                    setCount: capabilities.setCount,
                    stateCount: capabilities.stateCount,
                    userSlotLimit: capabilities.userSlotLimit
                )
            }
            return Layout(modeCount: 0, setCount: 0, stateCount: 0, userSlotLimit: 0)
        case .unsupported:
            return Layout(modeCount: 0, setCount: 0, stateCount: 0, userSlotLimit: 0)
        }
    }

    public var allowsIngestAndApply: Bool { profile.allowsConfigurationPlan }
}

/// 0x94 实探：真任务图应答 vs 未知命令通用空包。不得把空包当成 Standard。
public enum AhaKeyLegacyTaskPictureProbe: Equatable, Sendable {
    case supportsTaskPictures
    case genericUnknownCommandAck
    case malformed

    /// `frame` 为完整 AA BB 94 … CC DD。
    public static func classify(frame: Data) -> AhaKeyLegacyTaskPictureProbe {
        guard frame.count >= 6,
              frame[0] == 0xAA, frame[1] == 0xBB, frame[2] == 0x94,
              frame[frame.count - 2] == 0xCC, frame[frame.count - 1] == 0xDD else {
            return .malformed
        }
        let status = frame[3]
        let payload = frame.dropFirst(4).dropLast(2)
        if payload.isEmpty, status == 0 {
            return .genericUnknownCommandAck
        }
        guard payload.count >= 10 else { return .malformed }
        return .supportsTaskPictures
    }
}

/// 无 0x99 之后的 firmware v1 + 0x94 实探结论。禁止用版本字符串猜协议。
public enum AhaKeyOLEDLegacyProbe {
    public static func negotiationState(
        firmwareMainVersion: Int?,
        taskPicture: AhaKeyLegacyTaskPictureProbe?
    ) -> AhaKeyReleaseNegotiationState {
        guard firmwareMainVersion == 1 else {
            return .noResponse(
                firmwareMainVersion: firmwareMainVersion,
                supportsLegacyTaskPictures: false
            )
        }
        guard let taskPicture else {
            return .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: false)
        }
        switch taskPicture {
        case .supportsTaskPictures:
            return .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: true)
        case .genericUnknownCommandAck, .malformed:
            return .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: false)
        }
    }
}

/// ingest/apply 前的唯一写前门。unsupported / 协商中不得碰 CAS/WAL。
public enum AhaKeyOLEDWritePreflight {
    public static let routingCapability = AhaKeyRuntimeDeviceCapability(rawValue: "oled-picture-routing")

    public static func allowsIngestAndApply(_ context: AhaKeyOLEDCompatibilityContext) -> Bool {
        context.allowsIngestAndApply
    }

    public static func allowsIngestAndApply(snapshot: AhaKeyRuntimeSnapshot?) -> Bool {
        guard let snapshot, let id = snapshot.activeDeviceID,
              let device = snapshot.devices.first(where: { $0.id == id }) else {
            return false
        }
        return device.capabilities.contains(routingCapability)
    }
}
