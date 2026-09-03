import Foundation

/// v0.3 C2：页面是最小写入对象。每个可写字段只归属一个页面。
public enum AhaKeyStudioPageID: Equatable, Hashable, Sendable {
    case key(modeSlot: UInt8, role: AhaKeyDesiredConfiguration.KeyRole)
    case lights(modeSlot: UInt8)
    case screen(modeSlot: UInt8)
    case lever
    case power
}

/// 可写入字段。归属由 `AhaKeyStudioFieldOwnership` 唯一决定。
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

/// 权威 baseline 从哪来。local cache 不能经此升格为 verified。
public enum AhaKeyStudioBaselineProvenance: Equatable, Sendable {
    case deviceReadback
    case writeConfirmation
    case absent
}

/// 单字段设备权威事实。缺失时不得用当前草稿填补。
public struct AhaKeyStudioFieldAuthority: Equatable, Sendable {
    public var value: AhaKeyStudioFieldValue?
    public var trust: AhaKeyStudioBaselineTrust
    public var provenance: AhaKeyStudioBaselineProvenance

    public init(
        value: AhaKeyStudioFieldValue?,
        trust: AhaKeyStudioBaselineTrust,
        provenance: AhaKeyStudioBaselineProvenance
    ) {
        self.value = value
        self.trust = trust
        self.provenance = provenance
    }

    public static let unknown = AhaKeyStudioFieldAuthority(
        value: nil,
        trust: .unknown,
        provenance: .absent
    )

    /// local cache / 空 provenance 不得变成 verified。
    public func resolvedBaseline() -> AhaKeyStudioFieldBaseline {
        switch provenance {
        case .deviceReadback:
            guard trust == .verified, let value else { return .unknown }
            return AhaKeyStudioFieldBaseline(trust: .verified, value: value)
        case .writeConfirmation:
            guard let value else { return .unknown }
            return AhaKeyStudioFieldBaseline(trust: .writeConfirmed, value: value)
        case .absent:
            return .unknown
        }
    }
}

public struct AhaKeyStudioTaskAssetDescriptor: Equatable, Sendable {
    public var fileURL: URL?
    public var framesPerSecond: Int
    public var declaredFrameCount: Int?
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(
        fileURL: URL? = nil,
        framesPerSecond: Int,
        declaredFrameCount: Int? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.fileURL = fileURL
        self.framesPerSecond = framesPerSecond
        self.declaredFrameCount = declaredFrameCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// 冻结字段值：单一 typed 边界，禁止跨文件拼/拆 fingerprint。
public enum AhaKeyStudioFieldValue: Equatable, Sendable {
    case keyAction(AhaKeyDesiredConfiguration.KeyAction)
    case text(String)
    case optionalText(String?)
    case integer(Int)
    case taskAsset(AhaKeyStudioTaskAssetDescriptor)

    public static func number(_ value: Int) -> AhaKeyStudioFieldValue {
        .integer(value)
    }

    public static func asset(
        path: String?,
        framesPerSecond: Int,
        declaredFrameCount: Int?,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) -> AhaKeyStudioFieldValue {
        let url = path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return .taskAsset(
            AhaKeyStudioTaskAssetDescriptor(
                fileURL: url,
                framesPerSecond: framesPerSecond,
                declaredFrameCount: declaredFrameCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        )
    }

    public var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var integerValue: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var keyActionValue: AhaKeyDesiredConfiguration.KeyAction? {
        if case .keyAction(let value) = self { return value }
        return nil
    }

    public var taskAssetValue: AhaKeyStudioTaskAssetDescriptor? {
        if case .taskAsset(let value) = self { return value }
        return nil
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
    /// 相对 local lastSyncedDraft 的用户编辑；nil cache 时为 true。不得单独决定 no-op。
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
    /// 每个被写入字段的 typed 值。key/light/screen 都必须可消费。
    public var values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue]
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
        values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue],
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
        self.values = values
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
    /// 无可信页缓存或缺必需字段，不得静默猜测。
    case missingTrustedPageCache
    case unsupportedProfile
    /// 当前草稿不能表达该页（lever/power）。
    case unsupportedPage
    case write(AhaKeyStudioScopedWritePlan)
}

/// 单一归属表：一份 descriptor registry 派生 page lookup、可写集、fieldIDs 与 required。
public enum AhaKeyStudioFieldOwnership {
    /// 灯条 IDE 状态 raw（0...8），与 BLE `IDEState` 对齐。
    public static let lightMappingStates: [UInt8] = Array(0...8)

    private struct Descriptor: Equatable, Sendable {
        var id: AhaKeyStudioFieldID
        var page: AhaKeyStudioPageID
        var writable: Bool
    }

    private static let descriptors: [Descriptor] = makeDescriptors()

    private static func makeDescriptors() -> [Descriptor] {
        var items: [Descriptor] = [
            Descriptor(id: .leverMacro, page: .lever, writable: false),
            Descriptor(id: .powerAction, page: .power, writable: false),
        ]
        for slot in UInt8(0)...UInt8(3) {
            for role in AhaKeyDesiredConfiguration.KeyRole.allCases {
                let page = AhaKeyStudioPageID.key(modeSlot: slot, role: role)
                items.append(Descriptor(id: .keyAction(modeSlot: slot, role: role), page: page, writable: true))
                items.append(Descriptor(id: .keyDescription(modeSlot: slot, role: role), page: page, writable: true))
                items.append(Descriptor(id: .keyVoicePreset(modeSlot: slot, role: role), page: page, writable: true))
            }
            let lights = AhaKeyStudioPageID.lights(modeSlot: slot)
            items.append(Descriptor(id: .lightBrightness(modeSlot: slot), page: lights, writable: true))
            for state in lightMappingStates {
                items.append(Descriptor(id: .lightMapping(modeSlot: slot, state: state), page: lights, writable: true))
            }
            let screen = AhaKeyStudioPageID.screen(modeSlot: slot)
            items.append(Descriptor(id: .screenStatusLine(modeSlot: slot), page: screen, writable: true))
            items.append(Descriptor(id: .screenFramesPerSecond(modeSlot: slot), page: screen, writable: true))
            items.append(Descriptor(id: .screenActiveSet(modeSlot: slot), page: screen, writable: true))
            for setIndex in 0...1 {
                for state in AhaKeyDesiredConfiguration.TaskDisplayState.allCases {
                    items.append(
                        Descriptor(
                            id: .screenTaskAsset(modeSlot: slot, setIndex: setIndex, state: state),
                            page: screen,
                            writable: true
                        )
                    )
                }
            }
        }
        return items
    }

    public static func isWritable(_ page: AhaKeyStudioPageID) -> Bool {
        descriptors.contains { $0.page == page && $0.writable }
    }

    public static func page(for field: AhaKeyStudioFieldID) -> AhaKeyStudioPageID {
        guard let descriptor = descriptors.first(where: { $0.id == field }) else {
            preconditionFailure("unowned field \(field)")
        }
        return descriptor.page
    }

    /// mapping 与 assembler 共用：当前草稿能表达的字段。lever/power 为空。
    public static func fieldIDs(on page: AhaKeyStudioPageID) -> [AhaKeyStudioFieldID] {
        descriptors.filter { $0.page == page && $0.writable }.map(\.id)
    }

    /// Standard 屏幕整组：C1 protocol plan 的 legacy states，不含 idle。
    public static func requiredFields(
        on page: AhaKeyStudioPageID,
        profile: AhaKeyOLEDCompatibilityProfile,
        selectedTaskSet: Int
    ) -> [AhaKeyStudioFieldID] {
        guard isWritable(page) else { return [] }
        guard case .screen(let slot) = page else { return [] }
        guard case .legacyStandard = profile else { return [] }
        guard let plan = AhaKeyTaskPictureProtocolPlan.make(.standard) else { return [] }
        let logical = min(1, max(0, selectedTaskSet))
        return plan.states.compactMap { protocolState in
            guard let state = AhaKeyDesiredConfiguration.TaskDisplayState(rawValue: UInt8(protocolState.rawValue)) else {
                return nil
            }
            return .screenTaskAsset(modeSlot: slot, setIndex: logical, state: state)
        }
    }

    /// 每个字段只出现在一个页面；用于回归唯一归属。
    public static func allOwnedFields() -> [AhaKeyStudioFieldID] {
        descriptors.map(\.id)
    }
}

public enum AhaKeyStudioPageDiffer {
    /// 严格 no-op 只能基于 verified，或与同一次成功写入内容精确相同的 writeConfirmed。
    /// unknown 与缺失 baseline 永远不是 no-op；`isDirty` 不得绕过。
    public static func isStrictNoOp(_ field: AhaKeyStudioFrozenField) -> Bool {
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
        case .verified, .writeConfirmed:
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
