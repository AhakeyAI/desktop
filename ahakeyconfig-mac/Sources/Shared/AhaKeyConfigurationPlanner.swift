import Foundation
import ImageIO

// MARK: - 声明式配置 planner（WBS-5.6 切片 1）
//
// 纯函数：把 `AhaKeyDesiredConfiguration` + 资源元数据 + 0x99 能力 + 协议模式
// 规划为「资源事务 + 基础配置事务」的声明式计划。输出只含语义步骤与槽位分配，
// 不含物理 opcode——opcode 映射归 device transport 层。
// current-only：非 current 协议直接拒绝（旧固件计划不在本卡范围）。

public enum AhaKeyConfigurationPlanner {

    // MARK: 策略（设备/协议预算，可注入测试）

    public struct Policy: Equatable, Sendable {
        /// 单个资源编码后字节上限。
        public var maxAssetBytes: UInt64
        /// 单素材解码内存上限（width × height × bytesPerPixel × frames）。
        public var maxDecodedMemoryBytes: UInt64
        /// 单素材帧数上限。
        public var maxFramesPerAsset: Int
        /// 解码内存估算的每像素字节数（RGBA）。
        public var bytesPerPixel: Int
        /// 允许的图片媒体类型。
        public var allowedImageMediaTypes: Set<String>

        public init(
            maxAssetBytes: UInt64,
            maxDecodedMemoryBytes: UInt64,
            maxFramesPerAsset: Int,
            bytesPerPixel: Int = 4,
            allowedImageMediaTypes: Set<String> = ["gif"]
        ) {
            self.maxAssetBytes = maxAssetBytes
            self.maxDecodedMemoryBytes = maxDecodedMemoryBytes
            self.maxFramesPerAsset = maxFramesPerAsset
            self.bytesPerPixel = bytesPerPixel
            self.allowedImageMediaTypes = allowedImageMediaTypes
        }

        /// current 协议默认预算：单资源 2 MiB、解码内存 16 MiB、单素材 30 帧。
        /// 帧上限与 `AhaKeyDeviceLayoutPolicy.framesPerSlot` 同一口径：planner 拒绝的，
        /// 上传/绑定绝不静默截断——声明数、上传数、绑定数三者恒等。
        public static let currentDefault = Policy(
            maxAssetBytes: 2 * 1024 * 1024,
            maxDecodedMemoryBytes: 16 * 1024 * 1024,
            maxFramesPerAsset: 30
        )
    }

    // MARK: 5.1 WAL 受理校验器（策略级；能力/协议级校验在 plan 时做）

    /// 生产受理校验器：挂在 `AhaKeyRuntimePersistentStore.acceptanceValidator`。
    /// 覆盖：desiredConfiguration 可解码、资源引用完整、媒体类型、字节/帧数/解码内存预算。
    /// 不信任申报元数据：帧数/尺寸/解码预算以 CAS 实际图片数据（CGImageSource 解析）为准，
    /// 申报与实际不一致即拒绝受理。
    /// 设备能力（modeCount/setCount/stateCount/槽位数）与 current-only 是连接态信息，
    /// 由 `plan(...)` 在执行前校验，不在本受理层。
    public struct AcceptanceValidator: AhaKeyRuntimePackageAcceptanceValidator {
        public let policy: Policy

        public init(policy: Policy = .currentDefault) {
            self.policy = policy
        }

        public func validate(
            package: AhaKeyConfigurationPackage,
            resources: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]
        ) throws {
            let desired = try AhaKeyDesiredConfiguration.decode(from: package.desiredConfiguration)
            let declared = Dictionary(uniqueKeysWithValues: package.resources.map { ($0.logicalIdentifier, $0) })
            for identifier in desired.referencedResources {
                guard let meta = declared[identifier] else {
                    throw AhaKeyRuntimePersistenceError.unexpectedResourceFiles
                }
                guard policy.allowedImageMediaTypes.contains(meta.mediaType.rawValue),
                      meta.byteCount > 0, meta.byteCount <= policy.maxAssetBytes else {
                    throw AhaKeyRuntimePersistenceError.resourceTooLarge(
                        limit: policy.maxAssetBytes, attempted: meta.byteCount
                    )
                }
            }
            // CAS 实际数据校验：申报 vs 实际帧数/尺寸/解码预算
            for mode in desired.modes {
                if let identifier = mode.oled.defaultAnimation {
                    try validateActualImage(
                        identifier: identifier,
                        declaredFrames: mode.oled.defaultAnimationFrames ?? 0,
                        declaredWidth: nil, declaredHeight: nil,
                        contents: resources[identifier]?.contents
                    )
                }
                for set in mode.oled.taskSets {
                    for asset in set.assets where asset.resource != nil {
                        let identifier = asset.resource!
                        try validateActualImage(
                            identifier: identifier,
                            declaredFrames: asset.declaredFrameCount ?? 0,
                            declaredWidth: asset.pixelWidth, declaredHeight: asset.pixelHeight,
                            contents: resources[identifier]?.contents
                        )
                    }
                }
            }
        }

        /// 以 CAS 实际图片为准：帧数/尺寸必须与申报一致，解码预算按实际值核算。
        private func validateActualImage(
            identifier: AhaKeyResourceIdentifier,
            declaredFrames: Int,
            declaredWidth: Int?, declaredHeight: Int?,
            contents: Data?
        ) throws {
            guard let contents,
                  let source = CGImageSourceCreateWithData(contents as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw AhaKeyRuntimePersistenceError.resourceMetadataMismatch(identifier.rawValue)
            }
            let actualFrames = CGImageSourceGetCount(source)
            guard declaredFrames == actualFrames else {
                throw AhaKeyRuntimePersistenceError.resourceMetadataMismatch(identifier.rawValue)
            }
            if let declaredWidth, declaredWidth != first.width {
                throw AhaKeyRuntimePersistenceError.resourceMetadataMismatch(identifier.rawValue)
            }
            if let declaredHeight, declaredHeight != first.height {
                throw AhaKeyRuntimePersistenceError.resourceMetadataMismatch(identifier.rawValue)
            }
            let decoded = UInt64(first.width) * UInt64(first.height)
                * UInt64(policy.bytesPerPixel) * UInt64(actualFrames)
            guard decoded <= policy.maxDecodedMemoryBytes else {
                throw AhaKeyRuntimePersistenceError.resourceTooLarge(
                    limit: policy.maxDecodedMemoryBytes, attempted: decoded
                )
            }
        }
    }

    // MARK: 拒绝原因（planner 校验，全部 fail-fast 在写入前）

    public enum Rejection: Error, Equatable, Sendable {
        /// 非 current 协议：current-only 计划拒绝。
        case unsupportedProtocol
        /// 模式槽位超出设备 modeCount。
        case modeSlotExceedsDevice(slot: UInt8, deviceModeCount: Int)
        /// 任务状态超出设备 stateCount。
        case taskStateUnsupported(state: UInt8, deviceStateCount: Int)
        /// 配置引用了 resources 数组里不存在的资源。
        case missingResource(AhaKeyResourceIdentifier)
        /// 资源媒体类型不允许。
        case disallowedMediaType(AhaKeyResourceIdentifier, String)
        /// 资源字节数超上限。
        case assetTooLarge(AhaKeyResourceIdentifier, bytes: UInt64, limit: UInt64)
        /// 素材帧数超上限。
        case tooManyFrames(AhaKeyResourceIdentifier, frames: Int, limit: Int)
        /// 解码内存超上限。
        case decodeMemoryExceeded(AhaKeyResourceIdentifier, bytes: UInt64, limit: UInt64)
        /// idle 任务素材与 defaultAnimation 不是同一 CAS 引用。
        case idleAnimationMismatch(idle: AhaKeyResourceIdentifier, defaultAnimation: AhaKeyResourceIdentifier)
        /// 设备容量不足：按实际帧占用折算的槽位需求超出用户槽位数。
        case deviceCapacityExceeded(slotsNeeded: Int, slotLimit: Int)
        /// 当前发布通道关闭图片资源包，配置却引用了 OLED 资源。
        case releaseResourcePackageNotAllowed
        /// 当前发布通道未开放基础写入。
        case releaseWriteNotAllowed
    }

    // MARK: 计划产物（声明式步骤）

    /// 资源上传步骤：逻辑资源 → 设备槽位（槽位分配是 planner 职责，提交方不可见）。
    public struct ResourceUpload: Equatable, Sendable {
        public let resource: AhaKeyConfigurationResource
        public let slotIndex: Int
    }

    /// 单个事务：一组要么全成功、要么按取消/恢复语义收尾的步骤。
    public struct PlannedTransaction: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            /// 图片资源上传（可断线 partial resume：槽位级幂等）。
            case resourceUpload
            /// 基础配置（键位/灯条/状态行/激活套图，非图片部分）。
            case baseConfiguration
        }

        public let kind: Kind
        /// kind == .resourceUpload 时的上传步骤。
        public let uploads: [ResourceUpload]
        /// kind == .baseConfiguration 时涉及的模式槽位。
        public let modeSlots: [UInt8]

        public static func resources(_ uploads: [ResourceUpload]) -> PlannedTransaction {
            PlannedTransaction(kind: .resourceUpload, uploads: uploads, modeSlots: [])
        }

        public static func base(modeSlots: [UInt8]) -> PlannedTransaction {
            PlannedTransaction(kind: .baseConfiguration, uploads: [], modeSlots: modeSlots)
        }
    }

    public struct Plan: Equatable, Sendable {
        /// 有序事务：先资源后基础配置（基础配置引用的槽位必须已就位）。
        public let transactions: [PlannedTransaction]
        /// 去重后资源 → 槽位映射（供事务执行与恢复对账）。
        public let slotAssignments: [AhaKeyResourceIdentifier: Int]
    }

    // MARK: 规划入口

    public static func plan(
        desired: AhaKeyDesiredConfiguration,
        resources: [AhaKeyConfigurationResource],
        capabilities: AhaKeyFirmwareCapabilities,
        protocolMode: AhaKeyProtocolMode,
        policy: Policy = .currentDefault,
        release: AhaKeyReleaseFeatureProjection? = nil
    ) -> Result<Plan, Rejection> {
        // 1. current-only
        guard protocolMode == .current else { return .failure(.unsupportedProtocol) }
        if let release {
            guard release.allowsBasicConfigurationWrite else {
                return .failure(.releaseWriteNotAllowed)
            }
            if !release.allowsResourcePackage,
               !desired.referencedResources.isEmpty || !resources.isEmpty {
                return .failure(.releaseResourcePackageNotAllowed)
            }
        }

        // 2. 结构对账：模式槽位 / 套图数 / 任务状态在设备能力内
        for mode in desired.modes {
            guard Int(mode.slot) < capabilities.modeCount else {
                return .failure(.modeSlotExceedsDevice(slot: mode.slot, deviceModeCount: capabilities.modeCount))
            }
            for set in mode.oled.taskSets {
                for asset in set.assets {
                    guard Int(asset.state.rawValue) < capabilities.stateCount else {
                        return .failure(.taskStateUnsupported(
                            state: asset.state.rawValue, deviceStateCount: capabilities.stateCount))
                    }
                }
            }
        }

        // 3. 资源校验：引用完整、媒体类型、字节/帧数/解码内存
        let resourceIndex = Dictionary(uniqueKeysWithValues: resources.map { ($0.logicalIdentifier, $0) })
        let referenced = desired.referencedResources
        for identifier in referenced.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let meta = resourceIndex[identifier] else {
                return .failure(.missingResource(identifier))
            }
            guard policy.allowedImageMediaTypes.contains(meta.mediaType.rawValue) else {
                return .failure(.disallowedMediaType(identifier, meta.mediaType.rawValue))
            }
            guard meta.byteCount > 0, meta.byteCount <= policy.maxAssetBytes else {
                return .failure(.assetTooLarge(identifier, bytes: meta.byteCount, limit: policy.maxAssetBytes))
            }
        }
        // 帧数与解码内存：按素材声明逐条校验（含 defaultAnimation；实际值由受理校验核对 CAS）
        for mode in desired.modes {
            if let identifier = mode.oled.defaultAnimation {
                let frames = mode.oled.defaultAnimationFrames ?? 0
                guard frames > 0, frames <= policy.maxFramesPerAsset else {
                    return .failure(.tooManyFrames(identifier, frames: frames, limit: policy.maxFramesPerAsset))
                }
            }
            for set in mode.oled.taskSets {
                for asset in set.assets where asset.resource != nil {
                    let identifier = asset.resource!
                    let frames = asset.declaredFrameCount ?? 0
                    guard frames <= policy.maxFramesPerAsset else {
                        return .failure(.tooManyFrames(identifier, frames: frames, limit: policy.maxFramesPerAsset))
                    }
                    let width = UInt64(asset.pixelWidth ?? 0)
                    let height = UInt64(asset.pixelHeight ?? 0)
                    let decoded = width * height * UInt64(policy.bytesPerPixel) * UInt64(frames)
                    guard decoded <= policy.maxDecodedMemoryBytes else {
                        return .failure(.decodeMemoryExceeded(identifier, bytes: decoded, limit: policy.maxDecodedMemoryBytes))
                    }
                }
            }
        }

        // 4. CAS 一致性：idle 任务素材若带 resource，必须与 defaultAnimation 同一引用
        for mode in desired.modes {
            guard let defaultAnimation = mode.oled.defaultAnimation else { continue }
            for set in mode.oled.taskSets {
                if let idleAsset = set.assets.first(where: { $0.state == .idle }),
                   let idleResource = idleAsset.resource,
                   idleResource != defaultAnimation {
                    return .failure(.idleAnimationMismatch(
                        idle: idleResource, defaultAnimation: defaultAnimation))
                }
            }
        }

        // 5. 设备容量：按实际帧占用核算，不是只数资源个数或槽数。
        let framesPerSlot = AhaKeyDeviceLayoutPolicy().framesPerSlot
        var declaredFrames: [AhaKeyResourceIdentifier: Int] = [:]
        for mode in desired.modes {
            if let identifier = mode.oled.defaultAnimation {
                declaredFrames[identifier] = mode.oled.defaultAnimationFrames ?? 0
            }
            for set in mode.oled.taskSets {
                for asset in set.assets where asset.resource != nil {
                    declaredFrames[asset.resource!] = asset.declaredFrameCount ?? 0
                }
            }
        }
        let ordered = referenced.sorted(by: { $0.rawValue < $1.rawValue })

        // 先算占用槽位再比容量（slot 步长固定 framesPerSlot，未满槽仍占空间）
        var nextSlot = 0
        for identifier in ordered {
            let frames = max(1, declaredFrames[identifier] ?? 0)
            nextSlot += Int(ceil(Double(frames) / Double(framesPerSlot)))
        }
        let occupiedFrames = nextSlot * framesPerSlot
        guard occupiedFrames <= capabilities.userSlotLimit else {
            return .failure(.deviceCapacityExceeded(
                slotsNeeded: occupiedFrames, slotLimit: capabilities.userSlotLimit))
        }

        // 6. 槽位分配 + 事务序列（槽位跨度 = 该资源实际占用的槽数）
        var assignments: [AhaKeyResourceIdentifier: Int] = [:]
        var uploads: [ResourceUpload] = []
        nextSlot = 0  // 复用容量计算后的游标
        for identifier in ordered {
            assignments[identifier] = nextSlot
            uploads.append(ResourceUpload(resource: resourceIndex[identifier]!, slotIndex: nextSlot))
            let frames = max(1, declaredFrames[identifier] ?? 0)
            nextSlot += Int(ceil(Double(frames) / Double(framesPerSlot)))
        }
        var transactions: [PlannedTransaction] = []
        if !uploads.isEmpty { transactions.append(.resources(uploads)) }
        // 有 OLED 资源的模式先跑 base（绑定/save），避免空图模式在 0x97/0x98 上永久失败
        // 导致后面带图模式永远执行不到、屏幕仍显示旧图。
        let pictureSlots = desired.modes.filter(Self.modeReferencesPictures).map(\.slot).sorted()
        let otherSlots = desired.modes.filter { !Self.modeReferencesPictures($0) }.map(\.slot).sorted()
        transactions.append(.base(modeSlots: pictureSlots + otherSlots))
        return .success(Plan(transactions: transactions, slotAssignments: assignments))
    }

    /// 模式是否引用了任意图片资源（default 或任务槽）。
    private static func modeReferencesPictures(_ mode: AhaKeyDesiredConfiguration.Mode) -> Bool {
        if mode.oled.defaultAnimation != nil { return true }
        return mode.oled.taskSets.contains { set in
            set.assets.contains { $0.resource != nil }
        }
    }
}
