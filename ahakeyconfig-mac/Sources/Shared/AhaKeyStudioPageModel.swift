import Foundation

/// v0.3 C2：页面是最小写入对象。每个可写字段只归属一个页面。
public enum AhaKeyStudioPageID: Equatable, Hashable, Sendable {
    case key(modeSlot: UInt8, role: AhaKeyDesiredConfiguration.KeyRole)
    case lights(modeSlot: UInt8)
    case screen(modeSlot: UInt8)
    case lever
    case power
}

/// 可写入字段。归属由 `AhaKeyStudioFieldOwnership.page(for:)` 唯一决定。
public enum AhaKeyStudioFieldID: Equatable, Hashable, Sendable {
    case keyAction(modeSlot: UInt8, role: AhaKeyDesiredConfiguration.KeyRole)
    case keyDescription(modeSlot: UInt8, role: AhaKeyDesiredConfiguration.KeyRole)
    case keyVoicePreset(modeSlot: UInt8, role: AhaKeyDesiredConfiguration.KeyRole)
    case lightBrightness(modeSlot: UInt8)
    case lightMapping(modeSlot: UInt8, state: UInt8)
    case screenStatusLine(modeSlot: UInt8)
    case screenFramesPerSecond(modeSlot: UInt8)
    case screenTaskAsset(
        modeSlot: UInt8,
        setIndex: Int,
        state: AhaKeyDesiredConfiguration.TaskDisplayState
    )
    case screenActiveSet(modeSlot: UInt8)
    case leverMacro
    case powerAction
}

/// 设备读回/fingerprint 是权威；local lastSyncedDraft 只是缓存。
public enum AhaKeyStudioBaselineTrust: Equatable, Sendable {
    /// 设备读回与当前值一致。
    case verified
    /// 设备已确认写入，但旧固件不可读回。
    case writeConfirmed
    /// 无可信设备事实。
    case unknown
}

/// 冻结字段值：用 canonical fingerprint 比较，避免把草稿对象泄漏进 Shared 组装器。
public struct AhaKeyStudioFieldValue: Equatable, Sendable {
    public var fingerprint: String
    public var resourceURL: URL?

    public init(fingerprint: String, resourceURL: URL? = nil) {
        self.fingerprint = fingerprint
        self.resourceURL = resourceURL
    }

    public static func text(_ value: String) -> AhaKeyStudioFieldValue {
        AhaKeyStudioFieldValue(fingerprint: "text:\(value)")
    }

    public static func number(_ value: Int) -> AhaKeyStudioFieldValue {
        AhaKeyStudioFieldValue(fingerprint: "int:\(value)")
    }

    public static func optionalText(_ value: String?) -> AhaKeyStudioFieldValue {
        AhaKeyStudioFieldValue(fingerprint: "opt:\(value ?? "")")
    }

    public static func asset(
        path: String?,
        framesPerSecond: Int,
        declaredFrameCount: Int?,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) -> AhaKeyStudioFieldValue {
        let url = path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return AhaKeyStudioFieldValue(
            fingerprint: "asset:\(path ?? "")|\(framesPerSecond)|\(declaredFrameCount ?? -1)|\(pixelWidth ?? -1)|\(pixelHeight ?? -1)",
            resourceURL: url
        )
    }
}

public struct AhaKeyStudioFieldBaseline: Equatable, Sendable {
    public var trust: AhaKeyStudioBaselineTrust
    public var value: AhaKeyStudioFieldValue?

    public init(trust: AhaKeyStudioBaselineTrust, value: AhaKeyStudioFieldValue? = nil) {
        self.trust = trust
        self.value = value
    }

    public static let unknown = AhaKeyStudioFieldBaseline(trust: .unknown, value: nil)
}

public struct AhaKeyStudioFrozenField: Equatable, Sendable {
    public var id: AhaKeyStudioFieldID
    public var value: AhaKeyStudioFieldValue
    public var isDirty: Bool
    public var baseline: AhaKeyStudioFieldBaseline

    public init(
        id: AhaKeyStudioFieldID,
        value: AhaKeyStudioFieldValue,
        isDirty: Bool,
        baseline: AhaKeyStudioFieldBaseline
    ) {
        self.id = id
        self.value = value
        self.isDirty = isDirty
        self.baseline = baseline
    }
}

/// 单一页面冻结快照。assembler 只读本页字段；其它页 dirty 不得进入。
public struct AhaKeyStudioPageSnapshot: Equatable, Sendable {
    public var pageID: AhaKeyStudioPageID
    public var profile: AhaKeyOLEDCompatibilityProfile
    /// 屏幕页用户当前选中的套图（0/1）；非屏幕页忽略。
    public var selectedTaskSet: Int
    /// 用户已确认“覆盖写入此页”。
    public var overwriteConfirmed: Bool
    public var fields: [AhaKeyStudioFrozenField]

    public init(
        pageID: AhaKeyStudioPageID,
        profile: AhaKeyOLEDCompatibilityProfile,
        selectedTaskSet: Int = 0,
        overwriteConfirmed: Bool = false,
        fields: [AhaKeyStudioFrozenField]
    ) {
        self.pageID = pageID
        self.profile = profile
        self.selectedTaskSet = selectedTaskSet
        self.overwriteConfirmed = overwriteConfirmed
        self.fields = fields
    }
}

public struct AhaKeyStudioScopedWritePlan: Equatable, Sendable {
    public var pageID: AhaKeyStudioPageID
    public var fieldMask: Set<AhaKeyStudioFieldID>
    public var overwriteSemantic: Bool
    public var writeTaskSetA: Bool
    public var writeTaskSetB: Bool
    /// 要激活的套图；Standard 为协议内隐式结果，仍记录选中套但不发 `0x97`。
    public var activateTaskSet: Int?
    public var emitsSetActiveSetOpcode: Bool
    /// C2 禁止自动镜像 idle/defaultAnimation。
    public var bindsDefaultAnimation: Bool
    public var resources: [AhaKeyStudioResourceInput]
    public var statusLine: String?
    public var framesPerSecond: Int?

    public init(
        pageID: AhaKeyStudioPageID,
        fieldMask: Set<AhaKeyStudioFieldID>,
        overwriteSemantic: Bool,
        writeTaskSetA: Bool,
        writeTaskSetB: Bool,
        activateTaskSet: Int?,
        emitsSetActiveSetOpcode: Bool,
        bindsDefaultAnimation: Bool = false,
        resources: [AhaKeyStudioResourceInput] = [],
        statusLine: String? = nil,
        framesPerSecond: Int? = nil
    ) {
        self.pageID = pageID
        self.fieldMask = fieldMask
        self.overwriteSemantic = overwriteSemantic
        self.writeTaskSetA = writeTaskSetA
        self.writeTaskSetB = writeTaskSetB
        self.activateTaskSet = activateTaskSet
        self.emitsSetActiveSetOpcode = emitsSetActiveSetOpcode
        self.bindsDefaultAnimation = bindsDefaultAnimation
        self.resources = resources
        self.statusLine = statusLine
        self.framesPerSecond = framesPerSecond
    }
}

public enum AhaKeyStudioPageAssembly: Equatable, Sendable {
    /// 零差异：不得创建 operation，不得 ingest/apply。
    case noOp
    /// 整组协议或 unknown baseline 需要用户确认覆盖。
    case requiresOverwriteConfirmation
    /// 无可信页缓存，不得静默补齐。
    case missingTrustedPageCache
    case unsupportedProfile
    case write(AhaKeyStudioScopedWritePlan)
}

public enum AhaKeyStudioFieldOwnership {
    public static func page(for field: AhaKeyStudioFieldID) -> AhaKeyStudioPageID {
        switch field {
        case .keyAction(let slot, let role),
             .keyDescription(let slot, let role),
             .keyVoicePreset(let slot, let role):
            return .key(modeSlot: slot, role: role)
        case .lightBrightness(let slot), .lightMapping(let slot, _):
            return .lights(modeSlot: slot)
        case .screenStatusLine(let slot),
             .screenFramesPerSecond(let slot),
             .screenTaskAsset(let slot, _, _),
             .screenActiveSet(let slot):
            return .screen(modeSlot: slot)
        case .leverMacro:
            return .lever
        case .powerAction:
            return .power
        }
    }

    /// 每个字段只出现在一个页面；用于回归唯一归属。
    public static func allOwnedFields() -> [AhaKeyStudioFieldID] {
        var fields: [AhaKeyStudioFieldID] = [.leverMacro, .powerAction]
        for slot in UInt8(0)...UInt8(3) {
            for role in AhaKeyDesiredConfiguration.KeyRole.allCases {
                fields.append(.keyAction(modeSlot: slot, role: role))
                fields.append(.keyDescription(modeSlot: slot, role: role))
                fields.append(.keyVoicePreset(modeSlot: slot, role: role))
            }
            fields.append(.lightBrightness(modeSlot: slot))
            fields.append(.lightMapping(modeSlot: slot, state: 0))
            fields.append(.screenStatusLine(modeSlot: slot))
            fields.append(.screenFramesPerSecond(modeSlot: slot))
            fields.append(.screenActiveSet(modeSlot: slot))
            for setIndex in 0...1 {
                for state in AhaKeyDesiredConfiguration.TaskDisplayState.allCases {
                    fields.append(.screenTaskAsset(modeSlot: slot, setIndex: setIndex, state: state))
                }
            }
        }
        return fields
    }
}

public enum AhaKeyStudioPageDiffer {
    /// 严格 no-op 只能基于 verified，或与同一次成功写入内容精确相同的 writeConfirmed。
    public static func isStrictNoOp(_ field: AhaKeyStudioFrozenField) -> Bool {
        guard field.isDirty else { return true }
        switch field.baseline.trust {
        case .verified:
            return field.baseline.value == field.value
        case .writeConfirmed:
            guard let baseline = field.baseline.value else { return false }
            return baseline == field.value
        case .unknown:
            return false
        }
    }

    public static func hasTrustedCache(_ field: AhaKeyStudioFrozenField) -> Bool {
        switch field.baseline.trust {
        case .verified:
            return field.baseline.value != nil
        case .writeConfirmed:
            return field.baseline.value != nil
        case .unknown:
            return false
        }
    }

    /// Standard 屏幕协议按整套任务图写入；其它剖面按字段独立写。
    public static func requiresWholeGroupWrite(
        pageID: AhaKeyStudioPageID,
        profile: AhaKeyOLEDCompatibilityProfile
    ) -> Bool {
        guard case .screen = pageID else { return false }
        if case .legacyStandard = profile { return true }
        return false
    }
}
