import Foundation

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

        /// current 协议默认预算：单资源 2 MiB、解码内存 16 MiB、单素材 120 帧。
        public static let currentDefault = Policy(
            maxAssetBytes: 2 * 1024 * 1024,
            maxDecodedMemoryBytes: 16 * 1024 * 1024,
            maxFramesPerAsset: 120
        )
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
        /// 去重后资源总数超出设备用户槽位数。
        case deviceCapacityExceeded(resources: Int, slots: Int)
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
        policy: Policy = .currentDefault
    ) -> Result<Plan, Rejection> {
        // 1. current-only
        guard protocolMode == .current else { return .failure(.unsupportedProtocol) }

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
        // 帧数与解码内存：按素材声明逐条校验
        for mode in desired.modes {
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

        // 4. 设备容量：去重资源数 ≤ 用户槽位数
        let ordered = referenced.sorted(by: { $0.rawValue < $1.rawValue })
        guard ordered.count <= capabilities.userSlotLimit else {
            return .failure(.deviceCapacityExceeded(resources: ordered.count, slots: capabilities.userSlotLimit))
        }

        // 5. 槽位分配 + 事务序列
        var assignments: [AhaKeyResourceIdentifier: Int] = [:]
        var uploads: [ResourceUpload] = []
        for (index, identifier) in ordered.enumerated() {
            assignments[identifier] = index
            uploads.append(ResourceUpload(resource: resourceIndex[identifier]!, slotIndex: index))
        }
        var transactions: [PlannedTransaction] = []
        if !uploads.isEmpty { transactions.append(.resources(uploads)) }
        transactions.append(.base(modeSlots: desired.modes.map(\.slot).sorted()))
        return .success(Plan(transactions: transactions, slotAssignments: assignments))
    }
}
