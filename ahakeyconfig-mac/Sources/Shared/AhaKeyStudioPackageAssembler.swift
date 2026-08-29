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
    public static func assemble(
        modes: [AhaKeyStudioModeInput]
    ) throws -> AhaKeyStudioAssembledConfiguration {
        guard !modes.isEmpty else { throw AhaKeyStudioPackageAssemblerError.emptyModes }

        var assembledModes: [AhaKeyDesiredConfiguration.Mode] = []
        var resourceInputs: [AhaKeyResourceIdentifier: AhaKeyStudioResourceInput] = [:]

        for mode in modes {
            let slot = mode.slot
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

            let keys = try mode.keys.map {
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
            let assembledOLED = try AhaKeyDesiredConfiguration.OLED(
                defaultAnimation: defaultIdentifier,
                defaultAnimationFrames: defaultIdentifier == nil
                    ? nil : doneAsset?.declaredFrameCount,
                statusLine: oled.statusLine,
                framesPerSecond: oled.framesPerSecond,
                taskSets: assembledSets,
                activeSet: oled.activeSet
            )
            let assembledLightBar = try AhaKeyDesiredConfiguration.LightBar(
                stateMappings: lightMappings,
                brightness: mode.lightBar.brightness
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
}
