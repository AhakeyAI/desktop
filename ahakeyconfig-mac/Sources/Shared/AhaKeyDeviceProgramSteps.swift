import Foundation

// MARK: - 设备线协议程序（WBS-5.6 切片 4）
//
// 声明式步骤 → 线协议程序的纯映射层。Studio 从此不发物理 opcode/槽位：
// 槽位布局（用户区从 0 起、每槽 taskSlotFrames 帧）由本模块独占决策。
// 输出为语义程序步骤；资源字节由 CAS digest 引用，执行期经 transport seam 取数。

/// 线协议程序步骤（纯值，可测试、可恢复对账）。
public enum AhaKeyDeviceProgramStep: Equatable, Sendable {
    /// 0x80/0x9B 预备写入：address 必须 4096 对齐（flash 扇区）。
    case prepareWrite(sessionID: UInt16?, chunkLength: Int, address: UInt32)
    /// 写数据块：从资源 digest 的 offset 取 length 字节（≤180B/包由执行层再切）。
    case writeResourceChunk(digest: AhaKeySHA256Digest, offset: Int, length: Int)
    /// 0x9A 中止会话（失败/取消收尾）。
    case abortSession(sessionID: UInt16?)
    /// 0x95 绑定任务图槽位（current 协议）。
    case bindTaskPicture(mode: UInt8, set: UInt8, state: UInt8,
                         startIndex: UInt16, frameCount: UInt16, intervalMs: UInt16)
    /// 0x97 设置激活套图。
    case setActiveTaskPictureSet(mode: UInt8, set: UInt8)
    /// 0x98 结束任务图写入（不替换每模式默认动画绑定）。
    case finishTaskPictureWrite
    /// 0x73/0x73 键位映射（shortcut）。
    case setKeyShortcut(mode: UInt8, keyIndex: UInt8, hidCodes: [UInt8])
    /// 0x73/0x74 固件宏。
    case setKeyMacro(mode: UInt8, keyIndex: UInt8, pairs: [UInt8])
    /// 0x73/0x75 键位描述（ASCII ≤20B）。
    case setKeyDescription(mode: UInt8, keyIndex: UInt8, text: String)
    /// 0x84 per-mode 灯效映射（9 状态）。
    case setLightMapping(mode: UInt8, effects: [UInt8])
    /// 0x85 全局亮度 1-100。
    case setBrightness(UInt8)
    /// 0x04 保存配置到 flash。
    case saveConfig
}

/// 槽位布局与程序生成策略。
public struct AhaKeyDeviceLayoutPolicy: Equatable, Sendable {
    /// 每用户槽位容纳的帧数（任务图单素材上限 30，对齐 taskOLEDMaxFrames）。
    public var framesPerSlot: Int
    /// flash 帧槽字节数。
    public var frameSlotBytes: Int
    /// RGB565 编码后每帧字节数（160×80×2）。flash 数据必须是编码帧，不是 CAS 源字节。
    public var encodedFrameBytes: Int
    /// 写入分块字节数（4096 对齐要求）。
    public var chunkBytes: Int
    /// 每帧间隔（ms）= 1000 / fps。
    public var defaultFrameIntervalFloor: UInt16

    public init(framesPerSlot: Int = 30, frameSlotBytes: Int = 28_672,
                encodedFrameBytes: Int = 25_600,
                chunkBytes: Int = 4096, defaultFrameIntervalFloor: UInt16 = 33) {
        self.framesPerSlot = framesPerSlot
        self.frameSlotBytes = frameSlotBytes
        self.encodedFrameBytes = encodedFrameBytes
        self.chunkBytes = chunkBytes
        self.defaultFrameIntervalFloor = defaultFrameIntervalFloor
    }

    /// planner 槽位号 → 用户区起始帧索引。用户资源从 `userRegionBase`（生产路径为 0）起编，
    /// 不得把 `factorySlotBase` 当作上传/绑定起点。
    public func startFrameIndex(slot: Int, userRegionBase: Int) -> UInt16 {
        UInt16(userRegionBase + slot * framesPerSlot)
    }
}

public enum AhaKeyConfigurationStepMapper {

    // MARK: - resource 步骤：编码帧 → flash 写入程序

    /// resource 步骤的上传程序：prepare+chunk 循环（会话式优先），末尾不写绑定
    /// （绑定属于 base 步骤，槽位引用必须先就位）。
    /// - 帧字节数固定为 RGB565 编码长度（默认 25600B/帧）；offset/length 索引的是
    ///   **编码后字节流**，由执行层把 CAS 源（GIF/PNG）先经 `AhaKeyOLEDFrameEncoderCore`
    ///   编码再切片——CAS 源字节绝不直接当 flash 数据。
    /// - session 按 chunk 轮换（对齐 Studio 生产路径：每块独立 0x9B 会话，
    ///   失败时可精确回滚当前块）。
    public static func resourceUploadProgram(
        digest: AhaKeySHA256Digest,
        slotIndex: Int,
        encodedFrameCount: Int,
        usesSessionUpload: Bool,
        capabilities: AhaKeyFirmwareCapabilities,
        layout: AhaKeyDeviceLayoutPolicy = .init()
    ) -> [AhaKeyDeviceProgramStep]? {
        let startFrame = layout.startFrameIndex(slot: slotIndex, userRegionBase: 0)
        let start = Int(startFrame)
        guard start < capabilities.userSlotLimit else { return nil }
        let requested = min(encodedFrameCount, layout.framesPerSlot)
        let remaining = capabilities.userSlotLimit - start
        // 完整请求必须落在 primary 0..<userSlotLimit；越界不得静默截短。
        guard requested > 0, requested <= remaining else { return nil }
        let frameBytes = layout.encodedFrameBytes
        var steps: [AhaKeyDeviceProgramStep] = []
        for frame in 0..<requested {
            let frameAddress = UInt32(Int(startFrame) + frame) * UInt32(layout.frameSlotBytes)
            var offset = 0
            while offset < frameBytes {
                let length = min(layout.chunkBytes, frameBytes - offset)
                let sessionID: UInt16? = usesSessionUpload ? UInt16.random(in: 1...UInt16.max) : nil
                steps.append(.prepareWrite(
                    sessionID: sessionID, chunkLength: length,
                    address: frameAddress + UInt32(offset)
                ))
                steps.append(.writeResourceChunk(
                    digest: digest,
                    offset: frame * frameBytes + offset,
                    length: length
                ))
                offset += length
            }
        }
        return steps
    }

    // MARK: - base 步骤：单模式基础配置程序

    /// base:mode:N 程序：键位（shortcut/macro/description）+ 灯效映射 + 亮度 +
    /// 任务图绑定（引用已上传槽位）+ 激活套图 + finish + save。
    public static func baseConfigurationProgram(
        mode: AhaKeyDesiredConfiguration.Mode,
        desired: AhaKeyDesiredConfiguration,
        plan: AhaKeyConfigurationPlanner.Plan,
        capabilities: AhaKeyFirmwareCapabilities,
        layout: AhaKeyDeviceLayoutPolicy = .init(),
        release: AhaKeyReleaseFeatureProjection? = nil
    ) -> [AhaKeyDeviceProgramStep]? {
        struct BindSpec {
            let setIndex: Int
            let state: UInt8
            let startFrame: UInt16
            let frameCount: UInt16
            let intervalMs: UInt16
        }
        var binds: [BindSpec] = []
        for (setIndex, set) in mode.oled.taskSets.enumerated() {
            for state in AhaKeyDesiredConfiguration.TaskDisplayState.allCases {
                let asset = effectiveAsset(
                    in: set, for: state,
                    defaultAnimation: mode.oled.defaultAnimation,
                    defaultFPS: mode.oled.framesPerSecond,
                    defaultAnimationFrames: mode.oled.defaultAnimationFrames
                )
                guard let identifier = asset.resource,
                      let slot = plan.slotAssignments[identifier],
                      let frames = asset.declaredFrameCount, frames > 0 else { continue }
                let startFrame = layout.startFrameIndex(slot: slot, userRegionBase: 0)
                let start = Int(startFrame)
                let remaining = capabilities.userSlotLimit - start
                guard start < capabilities.userSlotLimit, frames <= remaining else { return nil }
                let interval = max(layout.defaultFrameIntervalFloor, UInt16(1000 / asset.framesPerSecond))
                binds.append(BindSpec(
                    setIndex: setIndex, state: state.rawValue,
                    startFrame: startFrame, frameCount: UInt16(frames), intervalMs: interval
                ))
            }
        }

        var steps: [AhaKeyDeviceProgramStep] = []

        // 键位（声明式 action → 0x73 子类型帧）
        for key in mode.keys {
            let keyIndex = key.role.rawValue
            switch key.action {
            case .shortcut(let shortcut):
                steps.append(.setKeyShortcut(
                    mode: mode.slot, keyIndex: keyIndex,
                    hidCodes: shortcutHidCodes(shortcut)
                ))
            case .macro(let macroSteps):
                var pairs: [UInt8] = []
                for step in macroSteps { pairs.append(contentsOf: [step.action, step.param]) }
                steps.append(.setKeyMacro(mode: mode.slot, keyIndex: keyIndex, pairs: pairs))
            }
            if !key.description.isEmpty {
                steps.append(.setKeyDescription(mode: mode.slot, keyIndex: keyIndex, text: key.description))
            }
        }

        // 灯效：9 状态映射 + 亮度
        let effects = lightEffectRow(mode.lightBar)
        steps.append(.setLightMapping(mode: mode.slot, effects: effects))
        steps.append(.setBrightness(UInt8(mode.lightBar.brightness)))

        let allowsPictureWrites = release?.allowsPictureWrites ?? true
        if allowsPictureWrites {
            for bind in binds {
                steps.append(.bindTaskPicture(
                    mode: mode.slot, set: UInt8(bind.setIndex), state: bind.state,
                    startIndex: bind.startFrame, frameCount: bind.frameCount, intervalMs: bind.intervalMs
                ))
            }
        }

        // save 必须排在 0x97 之前。0x95 绑定自身的持久化发生在固件置 set magic 之前，
        // 只有显式 save 才会把带 magic 的 key_bund 落盘，否则重启 sanitize 会清空绑定。
        steps.append(.saveConfig)

        // 0x97 激活套图放最后：它写的是与 key_bund 无关的 EEPROM journal 环，
        // 一旦被设备拒绝，前面已落盘的键位/灯效/绑定不受影响。
        // 0x98 PICTURE_WRITE_END 属于 0x80 裸写会话收尾，current 每块已用 0x9B/0x81 结束，不再发。
        // desired.activeSet >= 0 就必须发 0x97。纯 mapper 读不到设备当前套图，
        // 不得用 binds.isEmpty 猜测「设备已经在目标套」而省略。
        // 发布通道关闭图片面时不得发 0x95/0x97。
        if allowsPictureWrites, mode.oled.activeSet >= 0 {
            steps.append(.setActiveTaskPictureSet(mode: mode.slot, set: UInt8(mode.oled.activeSet)))
        }
        return steps
    }

    // MARK: - 步骤分发

    /// 把 WAL 步骤标识映射为线协议程序。未知步骤返回 nil（调用方按永久失败处理）。
    public static func program(
        for stepID: AhaKeyRuntimeStepIdentifier,
        desired: AhaKeyDesiredConfiguration,
        plan: AhaKeyConfigurationPlanner.Plan,
        resources: [AhaKeyConfigurationResource],
        capabilities: AhaKeyFirmwareCapabilities,
        layout: AhaKeyDeviceLayoutPolicy = .init(),
        release: AhaKeyReleaseFeatureProjection? = nil
    ) -> [AhaKeyDeviceProgramStep]? {
        let raw = stepID.rawValue
        if raw.hasPrefix("resource:") {
            if let release, !release.allowsResourcePackage { return nil }
            let identifier = String(raw.dropFirst("resource:".count))
            guard let slot = plan.slotAssignments.first(where: { $0.key.rawValue == identifier })?.value,
                  let meta = resources.first(where: { $0.logicalIdentifier.rawValue == identifier }),
                  let frames = declaredFrames(for: identifier, in: desired) else { return nil }
            // 帧数取声明值（容量/上限由 planner 校验，实际值由受理校验核对 CAS），
            // 编码长度由 layout 固定；meta.byteCount 是 CAS 源（GIF）大小，不参与分块。
            return resourceUploadProgram(
                digest: meta.sha256, slotIndex: slot,
                encodedFrameCount: frames,
                usesSessionUpload: capabilities.supportsSessionUpload,
                capabilities: capabilities, layout: layout
            )
        }
        if raw.hasPrefix("base:mode:"), let slot = UInt8(raw.dropFirst("base:mode:".count)),
           let mode = desired.modes.first(where: { $0.slot == slot }) {
            return baseConfigurationProgram(
                mode: mode, desired: desired, plan: plan,
                capabilities: capabilities, layout: layout, release: release
            )
        }
        return nil
    }

    // MARK: - 私有

    /// shortcut → HID codes：修饰键有序在前（左到右 ctrl/shift/alt/cmd），主键在后。
    static func shortcutHidCodes(_ shortcut: AhaKeyDesiredConfiguration.Shortcut) -> [UInt8] {
        let order = ["control", "shift", "option", "command"]
        let left: [String: UInt8] = ["control": 0xE0, "shift": 0xE1, "option": 0xE2, "command": 0xE3]
        var codes: [UInt8] = []
        for name in order where shortcut.modifiers.contains(name) {
            if let code = left[name] { codes.append(code) }
        }
        if shortcut.keyCode != 0 { codes.append(shortcut.keyCode) }
        return codes
    }

    /// 灯效行：9 个 IDE 状态槽（raw 0...8），未声明状态补 off。
    static func lightEffectRow(_ lightBar: AhaKeyDesiredConfiguration.LightBar) -> [UInt8] {
        var row = [UInt8](repeating: 0, count: 9) // 0 = off 固件索引约定
        for mapping in lightBar.stateMappings where Int(mapping.state) < 9 {
            row[Int(mapping.state)] = firmwareEffectIndex(mapping.effect)
        }
        return row
    }

    /// LightEffectStyle rawValue → 固件灯效索引（0=off；未知按 0 处理）。
    static func firmwareEffectIndex(_ effect: String) -> UInt8 {
        let table: [String: UInt8] = [
            "off": 0, "singleMove": 1, "breathing": 2, "pulseCenter": 3,
            "approvalWait": 4, "successSweep": 5, "rainbowWave": 6, "middleLight": 7,
        ]
        return table[effect] ?? 0
    }

    /// idle 无独立资源时优先回退 defaultAnimation；若仍无资源，则回退 working。
    static func effectiveAsset(
        in set: AhaKeyDesiredConfiguration.TaskSet,
        for state: AhaKeyDesiredConfiguration.TaskDisplayState,
        defaultAnimation: AhaKeyResourceIdentifier? = nil,
        defaultFPS: Int = 12,
        defaultAnimationFrames: Int? = nil
    ) -> AhaKeyDesiredConfiguration.TaskAsset {
        if let asset = set.assets.first(where: { $0.state == state }), asset.resource != nil {
            return asset
        }
        if state == .idle, let defaultAnimation {
            let frames = defaultAnimationFrames ?? 1
            return try! .init(state: .idle, resource: defaultAnimation, framesPerSecond: defaultFPS,
                              pixelWidth: 160, pixelHeight: 80, declaredFrameCount: frames)
        }
        if state == .idle,
           let working = set.assets.first(where: { $0.state == .working }), working.resource != nil {
            return working
        }
        return set.assets.first(where: { $0.state == state })
            ?? (try! .init(state: state, resource: nil, framesPerSecond: 12))
    }

    /// 资源声明帧数：任务素材取 TaskAsset.declaredFrameCount；defaultAnimation 取 OLED 字段。
    static func declaredFrames(for identifier: String, in desired: AhaKeyDesiredConfiguration) -> Int? {
        for mode in desired.modes {
            if mode.oled.defaultAnimation?.rawValue == identifier {
                return mode.oled.defaultAnimationFrames
            }
            for set in mode.oled.taskSets {
                for asset in set.assets where asset.resource?.rawValue == identifier {
                    return asset.declaredFrameCount
                }
            }
        }
        return nil
    }
}
