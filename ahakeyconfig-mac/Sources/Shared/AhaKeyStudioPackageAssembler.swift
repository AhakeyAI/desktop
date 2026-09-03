import Foundation

// MARK: - WBS 5.7 切片 2：Studio 编辑态 → AhaKeyConfigurationPackage 组装器
//
// 纯函数层：把「与 draft 无关的扁平输入」（`AhaKeyStudioModeInput` 族）组装为已冻结的
// `AhaKeyDesiredConfiguration` + 资源输入清单。本层不读文件、不做 I/O；文件读取与
// 摘要计算在 `AhaKeyStudioRuntimeFacade.apply` 中经可注入的 resource loader 完成。
//
// 冻结语义对齐（AhaKeyConfigurationPlanner / AcceptanceValidator）：
// - 资源是可供 CAS 受理的 GIF；Studio facade 在组装前必须已跑过同源 OLED 编码核心，
//   申报帧数/160×80 来自规范化结果。本层仍不读文件、不做编码。
//   每素材抽帧上限是固定 framesPerSlot（当前 30），不是本次 0x99 userSlotLimit。
// - `defaultAnimation` 镜像套图 A 的 done 槽：同一逻辑标识符 "mode{slot}-default"，
//   done 槽无资源时 defaultAnimation 为 nil。
// - 任意套图的 idle 槽若带资源，必须与 defaultAnimation 同引用（planner 规则 4：
//   `idleAnimationMismatch`）；输入违反时本层提前抛错，不产出 Runtime 必拒的包。
// - `taskGIFSchemaVersion` 是设备同步追踪字段，不进 canonical 包；`activeSet` 透传
//   （-1 = 尚未同步基线，跨重启保留）。

/// 组装器错误（全部 fail-fast，不产生半成品包）。
public enum AhaKeyStudioPackageAssemblerError: Error, Equatable {
    /// 至少需要一个模式。
    case emptyModes
    /// 每个模式的任务套图必须恰好 2 套（A/B）。
    case invalidTaskSetCount(mode: UInt8, count: Int)
    /// 素材带本地文件但缺少申报元数据（帧数/宽高）。
    case missingAssetMetadata(identifier: String)
    /// idle 槽资源必须镜像 defaultAnimation（planner 冻结约束）。
    case idleResourceMustMirrorDefaultAnimation(mode: UInt8)
}

// MARK: - 输入（扁平、Sendable、与 draft 模型无关）

/// 单键输入：字段与 `AhaKeyDesiredConfiguration.Key` 一一对应。
public struct AhaKeyStudioKeyInput: Equatable, Sendable {
    public var role: AhaKeyDesiredConfiguration.KeyRole
    public var action: AhaKeyDesiredConfiguration.KeyAction
    public var description: String
    public var voicePreset: String?

    public init(
        role: AhaKeyDesiredConfiguration.KeyRole,
        action: AhaKeyDesiredConfiguration.KeyAction,
        description: String,
        voicePreset: String? = nil
    ) {
        self.role = role
        self.action = action
        self.description = description
        self.voicePreset = voicePreset
    }
}

/// 任务状态素材输入：带本地文件 URL（提交方实现细节，不进 canonical 形态）与申报元数据。
public struct AhaKeyStudioTaskAssetInput: Equatable, Sendable {
    public var state: AhaKeyDesiredConfiguration.TaskDisplayState
    /// 本地 GIF 路径；nil = 该状态无独立图。
    public var localFileURL: URL?
    /// 5...20（由 TaskAsset 校验）。
    public var framesPerSecond: Int
    /// 申报帧数（有 localFileURL 时必填；facade 在读文件时复核实际值）。
    public var declaredFrameCount: Int?
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(
        state: AhaKeyDesiredConfiguration.TaskDisplayState,
        localFileURL: URL? = nil,
        framesPerSecond: Int,
        declaredFrameCount: Int? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.state = state
        self.localFileURL = localFileURL
        self.framesPerSecond = framesPerSecond
        self.declaredFrameCount = declaredFrameCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct AhaKeyStudioTaskSetInput: Equatable, Sendable {
    public var assets: [AhaKeyStudioTaskAssetInput]

    public init(assets: [AhaKeyStudioTaskAssetInput]) {
        self.assets = assets
    }
}

public struct AhaKeyStudioOLEDInput: Equatable, Sendable {
    public var statusLine: String
    /// 模式级默认动画 fps（1...30）。
    public var framesPerSecond: Int
    /// 恒 2 套（A/B）。
    public var taskSets: [AhaKeyStudioTaskSetInput]
    /// 激活套图 0/1；-1 = 尚未同步基线。
    public var activeSet: Int

    public init(
        statusLine: String,
        framesPerSecond: Int,
        taskSets: [AhaKeyStudioTaskSetInput],
        activeSet: Int
    ) {
        self.statusLine = statusLine
        self.framesPerSecond = framesPerSecond
        self.taskSets = taskSets
        self.activeSet = activeSet
    }
}

public struct AhaKeyStudioLightMappingInput: Equatable, Sendable {
    /// IDE 状态（UInt8 raw，对齐 IDEState）。
    public var state: UInt8
    /// 灯效标识（对齐 LightEffectStyle rawValue）。
    public var effect: String

    public init(state: UInt8, effect: String) {
        self.state = state
        self.effect = effect
    }
}

public struct AhaKeyStudioLightBarInput: Equatable, Sendable {
    public var stateMappings: [AhaKeyStudioLightMappingInput]
    /// 1...100。
    public var brightness: Int

    public init(stateMappings: [AhaKeyStudioLightMappingInput], brightness: Int) {
        self.stateMappings = stateMappings
        self.brightness = brightness
    }
}

public struct AhaKeyStudioModeInput: Equatable, Sendable {
    /// 模式槽位 0...3。
    public var slot: UInt8
    public var keys: [AhaKeyStudioKeyInput]
    public var oled: AhaKeyStudioOLEDInput
    public var lightBar: AhaKeyStudioLightBarInput

    public init(
        slot: UInt8,
        keys: [AhaKeyStudioKeyInput],
        oled: AhaKeyStudioOLEDInput,
        lightBar: AhaKeyStudioLightBarInput
    ) {
        self.slot = slot
        self.keys = keys
        self.oled = oled
        self.lightBar = lightBar
    }
}

// MARK: - 输出

/// 待 ingest 的资源输入：逻辑标识符 + 本地文件 + 申报元数据（facade 读文件后复核）。
public struct AhaKeyStudioResourceInput: Equatable, Sendable {
    public var logicalIdentifier: AhaKeyResourceIdentifier
    public var fileURL: URL
    public var declaredFrameCount: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        logicalIdentifier: AhaKeyResourceIdentifier,
        fileURL: URL,
        declaredFrameCount: Int,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.logicalIdentifier = logicalIdentifier
        self.fileURL = fileURL
        self.declaredFrameCount = declaredFrameCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct AhaKeyStudioAssembledConfiguration: Equatable, Sendable {
    public var configuration: AhaKeyDesiredConfiguration
    /// 去重（按逻辑标识符）且按标识符排序的资源输入清单。
    public var resources: [AhaKeyStudioResourceInput]

    public init(configuration: AhaKeyDesiredConfiguration, resources: [AhaKeyStudioResourceInput]) {
        self.configuration = configuration
        self.resources = resources
    }
}

// MARK: - 组装器

public enum AhaKeyStudioPackageAssembler {

    /// 任务状态 → 标识符片段（稳定字符串，供资源标识符派生）。
    private static func stateName(_ state: AhaKeyDesiredConfiguration.TaskDisplayState) -> String {
        switch state {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        case .done: return "done"
        }
    }

    /// 默认动画标识符：套图 A done 槽的镜像引用。
    public static func defaultAnimationIdentifier(mode slot: UInt8) -> String {
        "mode\(slot)-default"
    }

    /// 套图素材标识符（default 槽除外）。
    public static func taskAssetIdentifier(
        mode slot: UInt8,
        set: Int,
        state: AhaKeyDesiredConfiguration.TaskDisplayState
    ) -> String {
        "mode\(slot)-set\(set)-\(stateName(state))"
    }

    /// 组装：输入 → (canonical desired configuration, 资源输入清单)。
    /// 构造校验全部在这里（角色去重/套图数/fps 范围等由 DesiredConfiguration 各 init 兜底）。
    /// - Parameter includePictureResources: false 时忽略旧 OLED 草稿，产出中性空 OLED 的键位/灯效包。
    public static func assemble(
        modes: [AhaKeyStudioModeInput],
        includePictureResources: Bool
    ) throws -> AhaKeyStudioAssembledConfiguration {
        guard !modes.isEmpty else { throw AhaKeyStudioPackageAssemblerError.emptyModes }

        var assembledModes: [AhaKeyDesiredConfiguration.Mode] = []
        var resourceInputs: [AhaKeyResourceIdentifier: AhaKeyStudioResourceInput] = [:]

        for mode in modes {
            let slot = mode.slot
            let keys = mode.keys.map {
                AhaKeyDesiredConfiguration.Key(
                    role: $0.role,
                    action: $0.action,
                    description: $0.description,
                    voicePreset: $0.voicePreset
                )
            }
            let lightMappings = try mode.lightBar.stateMappings.map {
                try AhaKeyDesiredConfiguration.LightStateMapping(state: $0.state, effect: $0.effect)
            }
            let assembledLightBar = try AhaKeyDesiredConfiguration.LightBar(
                stateMappings: lightMappings,
                brightness: mode.lightBar.brightness
            )

            if !includePictureResources {
                assembledModes.append(try AhaKeyDesiredConfiguration.Mode(
                    slot: slot,
                    keys: keys,
                    oled: try keysAndLightNeutralOLED(),
                    lightBar: assembledLightBar
                ))
                continue
            }

            let oled = mode.oled
            guard oled.taskSets.count == 2 else {
                throw AhaKeyStudioPackageAssemblerError.invalidTaskSetCount(
                    mode: slot, count: oled.taskSets.count
                )
            }

            // 套图 A done 槽：defaultAnimation 镜像源。
            let doneAsset = oled.taskSets[0].assets.first { $0.state == .done }
            let doneURL = doneAsset?.localFileURL
            var defaultIdentifier: AhaKeyResourceIdentifier?
            if let doneURL {
                let identifier = try AhaKeyResourceIdentifier(defaultAnimationIdentifier(mode: slot))
                try register(
                    resourceInputs: &resourceInputs,
                    identifier: identifier,
                    asset: doneAsset!,
                    url: doneURL
                )
                defaultIdentifier = identifier
            }

            var assembledSets: [AhaKeyDesiredConfiguration.TaskSet] = []
            for (setIndex, set) in oled.taskSets.enumerated() {
                var assembledAssets: [AhaKeyDesiredConfiguration.TaskAsset] = []
                for asset in set.assets {
                    var resourceIdentifier: AhaKeyResourceIdentifier?
                    // 素材的申报元数据：镜像槽（idle / 套图 A done）一律取 done 源，保证同引用同元数据。
                    var metadataSource = asset
                    if let url = asset.localFileURL {
                        switch asset.state {
                        case .idle:
                            // planner 冻结约束：idle 带资源必须同 defaultAnimation 引用。
                            guard let doneURL, url == doneURL, let defaultIdentifier, let doneAsset else {
                                throw AhaKeyStudioPackageAssemblerError
                                    .idleResourceMustMirrorDefaultAnimation(mode: slot)
                            }
                            resourceIdentifier = defaultIdentifier
                            metadataSource = doneAsset
                        case .done where setIndex == 0:
                            resourceIdentifier = defaultIdentifier
                            if let doneAsset { metadataSource = doneAsset }
                        default:
                            let identifier = try AhaKeyResourceIdentifier(
                                taskAssetIdentifier(mode: slot, set: setIndex, state: asset.state)
                            )
                            try register(
                                resourceInputs: &resourceInputs,
                                identifier: identifier,
                                asset: asset,
                                url: url
                            )
                            resourceIdentifier = identifier
                        }
                    }
                    assembledAssets.append(try AhaKeyDesiredConfiguration.TaskAsset(
                        state: asset.state,
                        resource: resourceIdentifier,
                        framesPerSecond: asset.framesPerSecond,
                        pixelWidth: resourceIdentifier == nil ? nil : metadataSource.pixelWidth,
                        pixelHeight: resourceIdentifier == nil ? nil : metadataSource.pixelHeight,
                        declaredFrameCount: resourceIdentifier == nil ? nil : metadataSource.declaredFrameCount
                    ))
                }
                assembledSets.append(try AhaKeyDesiredConfiguration.TaskSet(assets: assembledAssets))
            }

            let assembledOLED = try AhaKeyDesiredConfiguration.OLED(
                defaultAnimation: defaultIdentifier,
                defaultAnimationFrames: defaultIdentifier == nil
                    ? nil : doneAsset?.declaredFrameCount,
                statusLine: oled.statusLine,
                framesPerSecond: oled.framesPerSecond,
                taskSets: assembledSets,
                activeSet: oled.activeSet
            )
            assembledModes.append(try AhaKeyDesiredConfiguration.Mode(
                slot: slot,
                keys: keys,
                oled: assembledOLED,
                lightBar: assembledLightBar
            ))
        }

        let configuration = try AhaKeyDesiredConfiguration(modes: assembledModes)
        let resources = resourceInputs.values.sorted { $0.logicalIdentifier.rawValue < $1.logicalIdentifier.rawValue }
        return AhaKeyStudioAssembledConfiguration(configuration: configuration, resources: resources)
    }

    /// 键位/灯效包使用的中性 OLED：不读取、不校验调用方草稿。
    private static func keysAndLightNeutralOLED() throws -> AhaKeyDesiredConfiguration.OLED {
        let emptySet = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try .init(state: .idle, resource: nil, framesPerSecond: 12),
            try .init(state: .working, resource: nil, framesPerSecond: 12),
            try .init(state: .waiting, resource: nil, framesPerSecond: 12),
            try .init(state: .done, resource: nil, framesPerSecond: 12),
        ])
        return try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil,
            defaultAnimationFrames: nil,
            statusLine: "",
            framesPerSecond: 12,
            taskSets: [emptySet, emptySet],
            activeSet: -1
        )
    }

    /// 登记资源输入：申报元数据必须齐全且为正。
    private static func register(
        resourceInputs: inout [AhaKeyResourceIdentifier: AhaKeyStudioResourceInput],
        identifier: AhaKeyResourceIdentifier,
        asset: AhaKeyStudioTaskAssetInput,
        url: URL
    ) throws {
        guard let frames = asset.declaredFrameCount, frames > 0,
              let width = asset.pixelWidth, width > 0,
              let height = asset.pixelHeight, height > 0 else {
            throw AhaKeyStudioPackageAssemblerError.missingAssetMetadata(
                identifier: identifier.rawValue
            )
        }
        resourceInputs[identifier] = AhaKeyStudioResourceInput(
            logicalIdentifier: identifier,
            fileURL: url,
            declaredFrameCount: frames,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    /// C2R4：单一 field action kind 驱动校验、emitted 过滤、动作生成与空动作判断。
    public static func assembleScopedPage(
        _ snapshot: AhaKeyStudioPageSnapshot
    ) -> AhaKeyStudioPageAssembly {
        if case .unsupported = snapshot.profile {
            return .unsupportedProfile
        }
        guard AhaKeyStudioFieldOwnership.isWritable(snapshot.pageID) else {
            return .unsupportedPage
        }

        let owned = snapshot.fields.filter {
            AhaKeyStudioFieldOwnership.page(for: $0.id) == snapshot.pageID
        }
        let byID = Dictionary(uniqueKeysWithValues: owned.map { ($0.id, $0) })
        let dirtyAccepted = owned.filter { $0.isDirty && !AhaKeyStudioPageDiffer.isStrictNoOp($0) }
        if dirtyAccepted.isEmpty {
            return .noOp
        }

        let dirtyIDs = Set(dirtyAccepted.map(\.id))
        if needsValidatedSelection(dirtyIDs), !(0...1).contains(snapshot.selectedTaskSet) {
            return .missingTrustedPageCache
        }
        for field in dirtyAccepted where actionKind(of: field.id) == .activeSet {
            guard consumableTypedValue(for: field, snapshot: snapshot) != nil else {
                return .missingTrustedPageCache
            }
        }

        let writingPictures = dirtyIDs.contains { actionKind(of: $0) == .taskAsset }
        let wholeGroup = AhaKeyStudioPageDiffer.requiresWholeGroupWrite(
            pageID: snapshot.pageID,
            profile: snapshot.profile
        )
        let required = AhaKeyStudioFieldOwnership.requiredFields(
            on: snapshot.pageID,
            profile: snapshot.profile,
            selectedTaskSet: snapshot.selectedTaskSet
        )
        var acceptedIDs = Set(dirtyIDs.filter { id in
            isEmittedLogicalField(id, snapshot: snapshot, acceptedIDs: dirtyIDs)
        })
        if writingPictures, wholeGroup, !snapshot.overwriteConfirmed {
            return .requiresOverwriteConfirmation
        }
        if writingPictures, wholeGroup {
            for fieldID in required {
                guard let field = byID[fieldID],
                      consumableTypedValue(for: field, snapshot: snapshot) != nil else {
                    return .missingTrustedPageCache
                }
                acceptedIDs.insert(fieldID)
            }
        }
        if acceptedIDs.isEmpty {
            return .noOp
        }

        let acceptedUnknown = acceptedIDs.contains { id in
            byID[id]?.baseline.trust == .unknown
        }
        if acceptedUnknown, !snapshot.overwriteConfirmed {
            return .requiresOverwriteConfirmation
        }
        for fieldID in acceptedIDs {
            guard let field = byID[fieldID],
                  consumableTypedValue(for: field, snapshot: snapshot) != nil else {
                return .missingTrustedPageCache
            }
        }

        var values: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue] = [:]
        var action = EmittedAction()
        for fieldID in acceptedIDs {
            guard let field = byID[fieldID],
                  let consumable = consumableTypedValue(for: field, snapshot: snapshot),
                  applyEmittedAction(
                    kind: actionKind(of: fieldID),
                    field: field,
                    value: consumable,
                    snapshot: snapshot,
                    into: &action
                  ) else {
                return .missingTrustedPageCache
            }
            values[fieldID] = consumable
        }

        let fieldMask = Set(values.keys)
        guard fieldMask == acceptedIDs else { return .missingTrustedPageCache }
        let hasEmittedAction = acceptedIDs.contains {
            hasPhysicalAction(kind: actionKind(of: $0), profile: snapshot.profile)
        }
        if !hasEmittedAction {
            return .noOp
        }

        let activation = AhaKeyOLEDSyncPlan.scopedScreenActivation(
            profile: snapshot.profile,
            selectedTaskSet: snapshot.selectedTaskSet,
            writesAnyTaskSet: action.writeSetA || action.writeSetB,
            activeSetIsDirty: action.activeSetDirty
        )

        return .write(
            AhaKeyStudioScopedWritePlan(
                pageID: snapshot.pageID,
                fieldMask: fieldMask,
                values: values,
                overwriteSemantic: snapshot.overwriteConfirmed && (wholeGroup || acceptedUnknown),
                writeTaskSetA: action.writeSetA,
                writeTaskSetB: action.writeSetB,
                activateTaskSet: activation?.selectedSet,
                emitsSetActiveSetOpcode: activation?.emitsSetActiveSetOpcode ?? false,
                bindsDefaultAnimation: false,
                resources: action.resources.sorted {
                    $0.logicalIdentifier.rawValue < $1.logicalIdentifier.rawValue
                },
                statusLine: action.statusLine,
                framesPerSecond: action.framesPerSecond
            )
        )
    }

    private enum FieldActionKind: Equatable {
        case keyAction
        case text
        case optionalText
        case integer
        case taskAsset
        case activeSet
        case unsupported
    }

    private struct EmittedAction {
        var resources: [AhaKeyStudioResourceInput] = []
        var writeSetA = false
        var writeSetB = false
        var statusLine: String?
        var framesPerSecond: Int?
        var activeSetDirty = false
    }

    private static func actionKind(of id: AhaKeyStudioFieldID) -> FieldActionKind {
        switch id {
        case .keyAction:
            return .keyAction
        case .keyDescription, .lightMapping, .screenStatusLine:
            return .text
        case .keyVoicePreset:
            return .optionalText
        case .lightBrightness, .screenFramesPerSecond:
            return .integer
        case .screenTaskAsset:
            return .taskAsset
        case .screenActiveSet:
            return .activeSet
        case .leverMacro, .powerAction:
            return .unsupported
        }
    }

    private static func needsValidatedSelection(_ ids: Set<AhaKeyStudioFieldID>) -> Bool {
        ids.contains {
            switch actionKind(of: $0) {
            case .taskAsset, .activeSet:
                return true
            default:
                return false
            }
        }
    }

    private static func hasPhysicalAction(
        kind: FieldActionKind,
        profile: AhaKeyOLEDCompatibilityProfile
    ) -> Bool {
        switch kind {
        case .keyAction, .text, .optionalText, .integer, .taskAsset:
            return true
        case .activeSet:
            return profile.pictureOpcodes.allowsSetActiveSet
        case .unsupported:
            return false
        }
    }

    private static func applyEmittedAction(
        kind: FieldActionKind,
        field: AhaKeyStudioFrozenField,
        value: AhaKeyStudioFieldValue,
        snapshot: AhaKeyStudioPageSnapshot,
        into action: inout EmittedAction
    ) -> Bool {
        switch kind {
        case .taskAsset:
            guard case .screenTaskAsset(_, let logicalSet, _) = field.id else { return false }
            if case .legacyStandard = snapshot.profile, logicalSet != snapshot.selectedTaskSet {
                return false
            }
            guard let resource = consumableResource(for: field, snapshot: snapshot) else {
                return false
            }
            let physical = AhaKeyOLEDSyncPlan.physicalTaskSetIndex(
                profile: snapshot.profile,
                logicalSet: logicalSet
            )
            if physical == 0 { action.writeSetA = true }
            if physical == 1 { action.writeSetB = true }
            action.resources.append(resource)
            return true
        case .text:
            if case .screenStatusLine = field.id {
                guard let text = value.textValue else { return false }
                action.statusLine = text
            }
            return true
        case .integer:
            if case .screenFramesPerSecond = field.id {
                guard let fps = value.integerValue else { return false }
                action.framesPerSecond = fps
            }
            return true
        case .activeSet:
            guard snapshot.profile.pictureOpcodes.allowsSetActiveSet else { return false }
            action.activeSetDirty = true
            return true
        case .keyAction, .optionalText:
            return true
        case .unsupported:
            return false
        }
    }

    private static func isEmittedLogicalField(
        _ id: AhaKeyStudioFieldID,
        snapshot: AhaKeyStudioPageSnapshot,
        acceptedIDs: Set<AhaKeyStudioFieldID>
    ) -> Bool {
        switch actionKind(of: id) {
        case .unsupported:
            return false
        case .activeSet:
            return snapshot.profile.pictureOpcodes.allowsSetActiveSet
        case .taskAsset:
            guard case .screenTaskAsset(_, let logicalSet, _) = id else { return false }
            if case .legacyStandard = snapshot.profile {
                let required = AhaKeyStudioFieldOwnership.requiredFields(
                    on: snapshot.pageID,
                    profile: snapshot.profile,
                    selectedTaskSet: snapshot.selectedTaskSet
                )
                return logicalSet == snapshot.selectedTaskSet && required.contains(id)
            }
            let dirtyLogicalSets = Set(acceptedIDs.compactMap { fieldID -> Int? in
                if case .screenTaskAsset(_, let setIndex, _) = fieldID { return setIndex }
                return nil
            })
            return AhaKeyOLEDSyncPlan.shouldWriteLogicalTaskSet(
                profile: snapshot.profile,
                logicalSet: logicalSet,
                selectedTaskSet: snapshot.selectedTaskSet,
                dirtyLogicalSets: dirtyLogicalSets
            )
        case .keyAction, .text, .optionalText, .integer:
            return true
        }
    }

    private static func consumableTypedValue(
        for field: AhaKeyStudioFrozenField,
        snapshot: AhaKeyStudioPageSnapshot
    ) -> AhaKeyStudioFieldValue? {
        switch actionKind(of: field.id) {
        case .keyAction:
            guard case .keyAction = field.value else { return nil }
            return field.value
        case .text:
            guard case .text = field.value else { return nil }
            return field.value
        case .optionalText:
            guard case .optionalText = field.value else { return nil }
            return field.value
        case .integer:
            guard case .integer = field.value else { return nil }
            return field.value
        case .activeSet:
            guard case .integer(let value) = field.value,
                  (0...1).contains(value),
                  value == snapshot.selectedTaskSet else {
                return nil
            }
            return field.value
        case .taskAsset:
            guard case .taskAsset = field.value,
                  consumableResource(for: field, snapshot: snapshot) != nil else {
                return nil
            }
            return field.value
        case .unsupported:
            return nil
        }
    }

    private static func consumableResource(
        for field: AhaKeyStudioFrozenField,
        snapshot: AhaKeyStudioPageSnapshot
    ) -> AhaKeyStudioResourceInput? {
        guard case .screenTaskAsset(_, let logicalSet, let state) = field.id else { return nil }
        if case .legacyStandard = snapshot.profile, case .idle = state {
            return nil
        }
        guard let asset = field.value.taskAssetValue,
              let url = asset.fileURL,
              let frames = asset.declaredFrameCount, frames > 0,
              asset.pixelWidth == 160,
              asset.pixelHeight == 80 else {
            return nil
        }
        let physical = AhaKeyOLEDSyncPlan.physicalTaskSetIndex(
            profile: snapshot.profile,
            logicalSet: logicalSet
        )
        guard let identifier = try? AhaKeyResourceIdentifier(
            taskAssetIdentifier(
                mode: modeSlot(of: snapshot.pageID) ?? 0,
                set: physical,
                state: state
            )
        ) else {
            return nil
        }
        return AhaKeyStudioResourceInput(
            logicalIdentifier: identifier,
            fileURL: url,
            declaredFrameCount: frames,
            pixelWidth: 160,
            pixelHeight: 80
        )
    }

    private static func modeSlot(of page: AhaKeyStudioPageID) -> UInt8? {
        switch page {
        case .key(let slot, _), .lights(let slot), .screen(let slot):
            return slot
        case .lever, .power:
            return nil
        }
    }
}
