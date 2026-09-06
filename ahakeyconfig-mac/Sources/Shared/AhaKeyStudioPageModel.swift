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
    /// Runtime 已确认的内容身份。缺省 nil；与 baseline 比较时优先用 digest。
    public var sha256: AhaKeySHA256Digest?
    public var byteCount: UInt64?
    public var mediaType: AhaKeyMediaType?

    public init(
        fileURL: URL? = nil,
        framesPerSecond: Int,
        declaredFrameCount: Int? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        sha256: AhaKeySHA256Digest? = nil,
        byteCount: UInt64? = nil,
        mediaType: AhaKeyMediaType? = nil
    ) {
        self.fileURL = fileURL
        self.framesPerSecond = framesPerSecond
        self.declaredFrameCount = declaredFrameCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sha256 = sha256
        self.byteCount = byteCount
        self.mediaType = mediaType
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        if let leftSHA = lhs.sha256, let rightSHA = rhs.sha256,
           let leftBytes = lhs.byteCount, let rightBytes = rhs.byteCount,
           let leftMedia = lhs.mediaType, let rightMedia = rhs.mediaType {
            return leftSHA == rightSHA
                && leftBytes == rightBytes
                && leftMedia == rightMedia
                && lhs.framesPerSecond == rhs.framesPerSecond
                && lhs.declaredFrameCount == rhs.declaredFrameCount
        }
        return lhs.fileURL == rhs.fileURL
            && lhs.framesPerSecond == rhs.framesPerSecond
            && lhs.declaredFrameCount == rhs.declaredFrameCount
            && lhs.pixelWidth == rhs.pixelWidth
            && lhs.pixelHeight == rhs.pixelHeight
            && lhs.sha256 == rhs.sha256
            && lhs.byteCount == rhs.byteCount
            && lhs.mediaType == rhs.mediaType
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
        pixelHeight: Int?,
        sha256: AhaKeySHA256Digest? = nil,
        byteCount: UInt64? = nil,
        mediaType: AhaKeyMediaType? = nil
    ) -> AhaKeyStudioFieldValue {
        let url = path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return .taskAsset(
            AhaKeyStudioTaskAssetDescriptor(
                fileURL: url,
                framesPerSecond: framesPerSecond,
                declaredFrameCount: declaredFrameCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                sha256: sha256,
                byteCount: byteCount,
                mediaType: mediaType
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
    /// 按 mode 冻结的 0x84 完整 9-state 行。不进入 fieldMask；只支撑整行重放。
    public var lightMappingRows: [UInt8: [UInt8]]

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
        framesPerSecond: Int? = nil,
        lightMappingRows: [UInt8: [UInt8]] = [:]
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
        self.lightMappingRows = lightMappingRows
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

/// C4：把 C2 assembly + C3 Runtime operation/FIFO 收成 Studio 页内交互投影。
/// 不创建第二套 assembler/Runtime 事实源。
public enum AhaKeyStudioPageStatus: Equatable, Sendable {
    case dirty
    case queued
    case writing
    case waitingReconnect
    case partial
    case writtenPendingVerify
    case synced
    case conflict
    case failed

    public var label: String {
        switch self {
        case .dirty: return "有修改"
        case .queued: return "排队中"
        case .writing: return "写入中"
        case .waitingReconnect: return "等待重连"
        case .partial: return "部分完成"
        case .writtenPendingVerify: return "已写入待验证"
        case .synced: return "已同步"
        case .conflict: return "冲突"
        case .failed: return "失败"
        }
    }
}

public enum AhaKeyStudioPageCommitKind: Equatable, Sendable {
    case writeCurrentPage
    case writeAndActivate
    case overwritePage
    case noModification

    public var title: String {
        switch self {
        case .writeCurrentPage: return "写入当前页"
        case .writeAndActivate: return "写入并激活"
        case .overwritePage: return "覆盖写入此页"
        case .noModification: return "无修改"
        }
    }
}

public struct AhaKeyStudioPageChrome: Equatable, Sendable {
    public var status: AhaKeyStudioPageStatus
    public var commitKind: AhaKeyStudioPageCommitKind
    public var isLocked: Bool
    public var canSubmit: Bool
    public var canRemoveQueued: Bool
    public var canCancelRunning: Bool
    public var canAbandon: Bool
    public var canRetryResidual: Bool
    public var queuePosition: Int?
    public var queuedBehindCount: Int
    public var operationID: AhaKeyRuntimeOperationID?

    public var statusLabel: String { status.label }
    public var commitButtonTitle: String { commitKind.title }

    public init(
        status: AhaKeyStudioPageStatus,
        commitKind: AhaKeyStudioPageCommitKind,
        isLocked: Bool,
        canSubmit: Bool,
        canRemoveQueued: Bool,
        canCancelRunning: Bool = false,
        canAbandon: Bool,
        canRetryResidual: Bool,
        queuePosition: Int?,
        queuedBehindCount: Int,
        operationID: AhaKeyRuntimeOperationID?
    ) {
        self.status = status
        self.commitKind = commitKind
        self.isLocked = isLocked
        self.canSubmit = canSubmit
        self.canRemoveQueued = canRemoveQueued
        self.canCancelRunning = canCancelRunning
        self.canAbandon = canAbandon
        self.canRetryResidual = canRetryResidual
        self.queuePosition = queuePosition
        self.queuedBehindCount = queuedBehindCount
        self.operationID = operationID
    }
}

public struct AhaKeyStudioPageChromeInput: Equatable, Sendable {
    public var pageID: AhaKeyStudioPageID
    public var assembly: AhaKeyStudioPageAssembly
    public var operation: AhaKeyRuntimeOperationSummary?
    public var deviceQueue: [AhaKeyRuntimeOperationSummary]
    public var isDeviceConnected: Bool
    public var pageBaselines: [AhaKeyRuntimeFieldBaseline]

    public init(
        pageID: AhaKeyStudioPageID,
        assembly: AhaKeyStudioPageAssembly,
        operation: AhaKeyRuntimeOperationSummary? = nil,
        deviceQueue: [AhaKeyRuntimeOperationSummary] = [],
        isDeviceConnected: Bool = true,
        pageBaselines: [AhaKeyRuntimeFieldBaseline] = []
    ) {
        self.pageID = pageID
        self.assembly = assembly
        self.operation = operation
        self.deviceQueue = deviceQueue
        self.isDeviceConnected = isDeviceConnected
        self.pageBaselines = pageBaselines
    }
}

public enum AhaKeyStudioPageChromeProjector {
    public static func project(_ input: AhaKeyStudioPageChromeInput) -> AhaKeyStudioPageChrome {
        let queueIndex = input.operation.flatMap { operation in
            input.deviceQueue.firstIndex(where: { $0.id == operation.id })
        }
        let queuePosition = queueIndex.map { $0 + 1 }
        let queuedBehindCount: Int
        if let queueIndex {
            queuedBehindCount = max(0, input.deviceQueue.count - queueIndex - 1)
        } else {
            queuedBehindCount = max(0, input.deviceQueue.count)
        }

        if let operation = input.operation, shouldProjectOperation(operation, assembly: input.assembly) {
            return projectOperation(
                operation,
                pageID: input.pageID,
                assembly: input.assembly,
                pageBaselines: input.pageBaselines,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount
            )
        }

        return projectAssembly(
            input.assembly,
            pageID: input.pageID,
            queuePosition: nil,
            queuedBehindCount: queuedBehindCount,
            operationID: nil
        )
    }

    public static func deviceFIFO(
        _ snapshot: AhaKeyRuntimeSnapshot,
        deviceID: AhaKeyRuntimeDeviceID
    ) -> [AhaKeyRuntimeOperationSummary] {
        snapshot.operations
            .filter { $0.targetDeviceID == deviceID && !$0.state.isTerminal }
            .sorted(by: AhaKeyRuntimeOperationSummary.durableFIFOLessThan)
    }

    public static func overlayResidualOnly(
        _ snapshot: AhaKeyStudioPageSnapshot,
        residualFieldIDs: Set<AhaKeyStudioFieldID>
    ) -> AhaKeyStudioPageSnapshot {
        AhaKeyStudioPageSnapshot(
            pageID: snapshot.pageID,
            profile: snapshot.profile,
            selectedTaskSet: snapshot.selectedTaskSet,
            overwriteConfirmed: snapshot.overwriteConfirmed,
            fields: snapshot.fields.map { field in
                guard residualFieldIDs.contains(field.id) else {
                    return AhaKeyStudioFrozenField(
                        id: field.id,
                        value: field.value,
                        isDirty: false,
                        baseline: .init(trust: .writeConfirmed, value: field.value)
                    )
                }
                return field
            }
        )
    }

    public static func pageTitle(_ pageID: AhaKeyStudioPageID) -> String {
        switch pageID {
        case .key(let slot, let role):
            return "Mode \(Int(slot) + 1) · \(keyRoleTitle(role))"
        case .lights(let slot):
            return "Mode \(Int(slot) + 1) · 灯条"
        case .screen(let slot):
            return "Mode \(Int(slot) + 1) · 屏幕"
        case .lever:
            return "拨杆"
        case .power:
            return "电源"
        }
    }

    private static func shouldProjectOperation(
        _ operation: AhaKeyRuntimeOperationSummary,
        assembly: AhaKeyStudioPageAssembly
    ) -> Bool {
        switch operation.state {
        case .completed:
            return assembly == .noOp
        case .accepted, .running, .paused, .cancellationRequested,
             .resumablePartial, .failedWithoutWrites, .failedWithPartialCommit:
            return true
        }
    }

    private static func projectOperation(
        _ operation: AhaKeyRuntimeOperationSummary,
        pageID: AhaKeyStudioPageID,
        assembly: AhaKeyStudioPageAssembly,
        pageBaselines: [AhaKeyRuntimeFieldBaseline],
        queuePosition: Int?,
        queuedBehindCount: Int
    ) -> AhaKeyStudioPageChrome {
        let residualRetry = !(operation.residual?.isEmpty ?? true)
        let canAbandon = operation.abandonEligibility?.eligible == true
        switch operation.state {
        case .accepted:
            return lockedChrome(
                status: .queued,
                pageID: pageID,
                canRemoveQueued: true,
                canAbandon: false,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operation.id
            )
        case .running, .cancellationRequested:
            return lockedChrome(
                status: .writing,
                pageID: pageID,
                canRemoveQueued: false,
                canAbandon: false,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operation.id
            )
        case .paused:
            return lockedChrome(
                status: .waitingReconnect,
                pageID: pageID,
                canRemoveQueued: false,
                canAbandon: canAbandon,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operation.id
            )
        case .resumablePartial:
            return lockedChrome(
                status: .partial,
                pageID: pageID,
                canRemoveQueued: false,
                canAbandon: canAbandon,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operation.id
            )
        case .failedWithPartialCommit:
            return unlockedTerminalChrome(
                status: residualRetry ? .partial : .failed,
                pageID: pageID,
                assembly: assembly,
                canRetryResidual: residualRetry,
                queuedBehindCount: queuedBehindCount,
                operationID: operation.id
            )
        case .failedWithoutWrites:
            let conflict = operation.messageCode == .configurationPreflightConflict
            return unlockedTerminalChrome(
                status: conflict ? .conflict : .failed,
                pageID: pageID,
                assembly: assembly,
                canRetryResidual: residualRetry,
                queuedBehindCount: queuedBehindCount,
                operationID: operation.id
            )
        case .completed:
            let pendingVerify = pageBaselines.contains { $0.trust == .writeConfirmed }
            return AhaKeyStudioPageChrome(
                status: pendingVerify ? .writtenPendingVerify : .synced,
                commitKind: .noModification,
                isLocked: false,
                canSubmit: false,
                canRemoveQueued: false,
                canCancelRunning: false,
                canAbandon: false,
                canRetryResidual: false,
                queuePosition: nil,
                queuedBehindCount: queuedBehindCount,
                operationID: operation.id
            )
        }
    }

    private static func projectAssembly(
        _ assembly: AhaKeyStudioPageAssembly,
        pageID: AhaKeyStudioPageID,
        queuePosition: Int?,
        queuedBehindCount: Int,
        operationID: AhaKeyRuntimeOperationID?
    ) -> AhaKeyStudioPageChrome {
        switch assembly {
        case .noOp:
            return AhaKeyStudioPageChrome(
                status: .synced,
                commitKind: .noModification,
                isLocked: false,
                canSubmit: false,
                canRemoveQueued: false,
                canCancelRunning: false,
                canAbandon: false,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operationID
            )
        case .requiresOverwriteConfirmation:
            return AhaKeyStudioPageChrome(
                status: .dirty,
                commitKind: .overwritePage,
                isLocked: false,
                canSubmit: true,
                canRemoveQueued: false,
                canCancelRunning: false,
                canAbandon: false,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operationID
            )
        case .write:
            let kind: AhaKeyStudioPageCommitKind
            if case .screen = pageID {
                kind = .writeAndActivate
            } else {
                kind = .writeCurrentPage
            }
            return AhaKeyStudioPageChrome(
                status: .dirty,
                commitKind: kind,
                isLocked: false,
                canSubmit: true,
                canRemoveQueued: false,
                canCancelRunning: false,
                canAbandon: false,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operationID
            )
        case .missingTrustedPageCache, .unsupportedProfile, .unsupportedPage:
            return AhaKeyStudioPageChrome(
                status: assembly == .unsupportedPage ? .synced : .failed,
                commitKind: .noModification,
                isLocked: false,
                canSubmit: false,
                canRemoveQueued: false,
                canCancelRunning: false,
                canAbandon: false,
                canRetryResidual: false,
                queuePosition: queuePosition,
                queuedBehindCount: queuedBehindCount,
                operationID: operationID
            )
        }
    }

    private static func lockedChrome(
        status: AhaKeyStudioPageStatus,
        pageID: AhaKeyStudioPageID,
        canRemoveQueued: Bool,
        canAbandon: Bool,
        canRetryResidual: Bool,
        queuePosition: Int?,
        queuedBehindCount: Int,
        operationID: AhaKeyRuntimeOperationID
    ) -> AhaKeyStudioPageChrome {
        AhaKeyStudioPageChrome(
            status: status,
            commitKind: .noModification,
            isLocked: true,
            canSubmit: false,
            canRemoveQueued: canRemoveQueued,
            canCancelRunning: false,
            canAbandon: canAbandon,
            canRetryResidual: canRetryResidual,
            queuePosition: queuePosition,
            queuedBehindCount: queuedBehindCount,
            operationID: operationID
        )
    }

    private static func unlockedTerminalChrome(
        status: AhaKeyStudioPageStatus,
        pageID: AhaKeyStudioPageID,
        assembly: AhaKeyStudioPageAssembly,
        canRetryResidual: Bool,
        queuedBehindCount: Int,
        operationID: AhaKeyRuntimeOperationID
    ) -> AhaKeyStudioPageChrome {
        let assemblyChrome = projectAssembly(
            assembly,
            pageID: pageID,
            queuePosition: nil,
            queuedBehindCount: queuedBehindCount,
            operationID: operationID
        )
        return AhaKeyStudioPageChrome(
            status: status,
            commitKind: canRetryResidual ? assemblyChrome.commitKind : .noModification,
            isLocked: false,
            canSubmit: canRetryResidual && assemblyChrome.canSubmit,
            canRemoveQueued: false,
            canCancelRunning: false,
            canAbandon: false,
            canRetryResidual: canRetryResidual,
            queuePosition: nil,
            queuedBehindCount: queuedBehindCount,
            operationID: operationID
        )
    }

    private static func keyRoleTitle(_ role: AhaKeyDesiredConfiguration.KeyRole) -> String {
        switch role {
        case .voice: return "Key 1"
        case .approve: return "Key 2"
        case .reject: return "Key 3"
        case .submit: return "Key 4"
        }
    }
}
