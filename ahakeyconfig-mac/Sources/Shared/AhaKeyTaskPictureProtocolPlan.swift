import Foundation

public enum AhaKeyTaskDisplayState: Int, Codable, CaseIterable, Identifiable {
    case idle = 0
    case working = 1
    case waiting = 2
    case done = 3

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .idle: return NSLocalizedString("待机", comment: "")
        case .working: return NSLocalizedString("工作中", comment: "")
        case .waiting: return NSLocalizedString("等待授权", comment: "")
        case .done: return NSLocalizedString("已完成 / 停止", comment: "")
        }
    }

    public static let legacyStates: [AhaKeyTaskDisplayState] = [.working, .waiting, .done]
}

/// LCD Inspector 的能力分区。普通默认图片（0x80 + 0x82）与任务状态图是两项独立能力。
public struct AhaKeyOLEDInspectorSections: Equatable {
    public let showsDefaultPictureEditor: Bool
    public let showsTaskPictureEditor: Bool

    public static func make(mode: AhaKeyProtocolMode) -> AhaKeyOLEDInspectorSections {
        AhaKeyOLEDInspectorSections(
            showsDefaultPictureEditor: mode == .legacyBaseOnly,
            showsTaskPictureEditor: mode == .legacy || mode == .current
        )
    }
}

public enum AhaKeyDefaultPictureSyncDecision: Equatable {
    case skip
    case clear
    case upload

    public static func decide(
        hasLocalAsset: Bool,
        assetChanged: Bool,
        deviceFrameCount: Int
    ) -> AhaKeyDefaultPictureSyncDecision {
        if assetChanged { return hasLocalAsset ? .upload : .clear }
        if hasLocalAsset, deviceFrameCount == 0 { return .upload }
        return .skip
    }
}

/// 任务图协议的纯策略层。BLE/UI 只消费这个计划，不再各自猜测固件代际。
public struct AhaKeyTaskPictureProtocolPlan: Equatable {
    public enum MetadataFormat: Equatable {
        case legacySingleSet
        case currentSetAware
    }

    public let metadataFormat: MetadataFormat
    public let setIndices: [Int]
    public let states: [AhaKeyTaskDisplayState]
    public let finishesRawUpload: Bool
    public let supportsActiveSet: Bool
    public let usesSessionUpload: Bool

    public static func make(
        mode: AhaKeyProtocolMode,
        capabilities: AhaKeyFirmwareCapabilities?
    ) -> AhaKeyTaskPictureProtocolPlan? {
        switch mode {
        case .legacy:
            return AhaKeyTaskPictureProtocolPlan(
                metadataFormat: .legacySingleSet,
                setIndices: [0],
                states: AhaKeyTaskDisplayState.legacyStates,
                finishesRawUpload: false,
                supportsActiveSet: false,
                usesSessionUpload: false
            )
        case .current:
            let setCount = min(2, max(1, capabilities?.setCount ?? 2))
            let supportsIdle = capabilities?.supportsIdleTaskPicture ?? true
            return AhaKeyTaskPictureProtocolPlan(
                metadataFormat: .currentSetAware,
                setIndices: Array(0 ..< setCount),
                states: supportsIdle ? AhaKeyTaskDisplayState.allCases : AhaKeyTaskDisplayState.legacyStates,
                finishesRawUpload: true,
                supportsActiveSet: setCount > 1,
                usesSessionUpload: capabilities?.supportsSessionUpload == true
            )
        case .negotiating, .legacyBaseOnly, .restrictedUnknown:
            return nil
        }
    }
}

/// 在用户槽与固件声明的回收槽中寻找第一段连续空闲空间。
public enum AhaKeyPictureSlotAllocator {
    public static func allocate(
        frameCount: Int,
        primaryRange: Range<Int>,
        reclaimRange: Range<Int>?,
        occupiedRanges: [Range<Int>]
    ) -> Int? {
        guard frameCount > 0 else { return nil }
        let allowedRanges = [primaryRange] + (reclaimRange.map { [$0] } ?? [])
        let occupied = occupiedRanges.sorted { $0.lowerBound < $1.lowerBound }
        for allowedRange in allowedRanges where !allowedRange.isEmpty {
            var candidate = allowedRange.lowerBound
            for region in occupied {
                if region.upperBound <= allowedRange.lowerBound || region.lowerBound >= allowedRange.upperBound {
                    continue
                }
                if candidate + frameCount <= region.lowerBound { break }
                candidate = max(candidate, region.upperBound)
            }
            if candidate + frameCount <= allowedRange.upperBound { return candidate }
        }
        return nil
    }
}

public enum AhaKeyTaskPictureSyncDecision: Equatable {
    public enum UploadReason: Equatable {
        case assetChanged
        case deviceSlotEmpty
        case deviceUsesFactoryAsset
        case overlapsDefaultPicture
        case schemaMigration
    }

    case skip
    case markSynchronizedWithoutWrite
    case clear
    case upload([UploadReason])

    public static func decide(
        hasLocalAsset: Bool,
        assetChanged: Bool,
        deviceStartIndex: Int,
        deviceFrameCount: Int,
        factorySlotBase: Int?,
        reclaimRange: Range<Int>?,
        overlapsDefaultPicture: Bool,
        deviceSchemaVersion: Int?
    ) -> AhaKeyTaskPictureSyncDecision {
        let usesReclaim = reclaimRange?.contains(deviceStartIndex) == true
        let usesFactory = deviceFrameCount > 0
            && factorySlotBase.map { deviceStartIndex >= $0 } == true
            && !usesReclaim

        guard hasLocalAsset else {
            if deviceFrameCount > 0, !usesFactory { return .clear }
            return assetChanged ? .markSynchronizedWithoutWrite : .skip
        }

        var reasons: [UploadReason] = []
        if assetChanged { reasons.append(.assetChanged) }
        if deviceFrameCount == 0 { reasons.append(.deviceSlotEmpty) }
        if usesFactory { reasons.append(.deviceUsesFactoryAsset) }
        if overlapsDefaultPicture { reasons.append(.overlapsDefaultPicture) }
        if (deviceSchemaVersion ?? 0) < 3 { reasons.append(.schemaMigration) }
        return reasons.isEmpty ? .skip : .upload(reasons)
    }
}

/// 0x9B 会话写入的数据子包编码。每个子包都必须重复 session 前缀；
/// 固件逐包校验此前缀，而不是只校验整块数据的第一包。
public enum AhaKeyPictureDataPacketizer {
    public static func packets(
        for data: Data,
        maxPacketLength: Int,
        sessionID: UInt16?
    ) -> [Data] {
        let packetLimit = max(1, maxPacketLength)
        let prefixLength = sessionID == nil ? 0 : 2
        let payloadLength = max(1, packetLimit - prefixLength)
        return stride(from: 0, to: data.count, by: payloadLength).map { offset in
            let end = min(offset + payloadLength, data.count)
            var packet = Data()
            if let sessionID {
                packet.append(UInt8(sessionID & 0xFF))
                packet.append(UInt8((sessionID >> 8) & 0xFF))
            }
            packet.append(data[offset ..< end])
            return packet
        }
    }
}
