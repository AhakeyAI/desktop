import Foundation

// MARK: - 固件能力协商（M1d：0x99 能力查询 + protocolMode 决策）
//
// 移植自 Rhino 线（AhaKeyProtocol.swift 的 AhaKeyFirmwareCapabilities/parseCapabilities、
// AhaKeyBLEManager.swift 的 queryFirmwareCapabilities/protocolMode）。
// 纯值类型 + 纯函数：不依赖 CoreBluetooth、不依赖 @MainActor，方便单元测试。
// AhaKeyBLEManager 在连接建立后执行协商，结果经 DeviceStateReducer 进入快照投影。

/// 协商出的协议模式。
/// - negotiating: 已连接、尚未完成 0x99 协商（每次连接/断开都会回到该状态）。
/// - legacy: 0x99 三次查询均无应答，且 firmwareMainVersion == 1（已知旧固件，走旧命令集）。
/// - legacyBaseOnly: 固件版本为 1，但 0x94 只返回未知命令的通用空应答；仅支持键位/灯效等基础配置。
/// - current: 0x99 应答 protocolVersion == 3（当前 Rhino 协议）。
/// - restrictedUnknown: 0x99 有应答但协议版本未知，或无应答且固件版本也不是已知旧版——
///   只保留最保守的只读能力，禁用写入类高级功能。
public enum AhaKeyProtocolMode: Equatable {
    case negotiating
    case legacy
    case legacyBaseOnly
    case current
    case restrictedUnknown

    /// USB 有线配置通道只允许在确认 current 协议的固件上启用。
    /// M3 移植 USB 传输时以此为唯一启用入口（R2a 防护：旧固件/未知固件不走 USB 写）。
    public var allowsUSBConfigurationTransport: Bool {
        self == .current
    }

    /// 任务图配置（0x93/0x95 路径选择是 M2 的事）只允许在已识别的协议上进行。
    public var allowsTaskPictureConfiguration: Bool {
        self == .legacy || self == .current
    }
}

/// 0x99 能力帧解析结果。长度变体：
/// - factory-off 14 字节：`factorySlotBase=0`（用户区从 0 起编）；
/// - factory compact 14 字节：`userSlotLimit` / reclaim 区间在帧内，`factorySlotBase=userSlotLimit`；
/// - factory 22/26 字节：出厂资源束扩展（26 另含 reclaim 覆盖字段）。
public struct AhaKeyFirmwareCapabilities: Equatable {
    public static let idleTaskPictureFlag: UInt16 = 1 << 0
    public static let factoryAssetsFlag: UInt16 = 1 << 2
    public static let sessionUploadFlag: UInt16 = 1 << 3

    public let protocolVersion: Int
    public let modeCount: Int
    public let setCount: Int
    public let stateCount: Int
    public let flags: UInt16
    public let maxPacketSize: Int
    public let userSlotLimit: Int
    public let factorySlotBase: Int
    public let factoryBundleVersion: UInt32
    public let factoryManifestCRC: UInt32
    public let factoryStatus: Int
    public let factoryError: Int
    public let reclaimSlotBase: Int
    public let reclaimSlotLimit: Int

    public init(
        protocolVersion: Int, modeCount: Int, setCount: Int, stateCount: Int,
        flags: UInt16, maxPacketSize: Int, userSlotLimit: Int, factorySlotBase: Int,
        factoryBundleVersion: UInt32, factoryManifestCRC: UInt32,
        factoryStatus: Int, factoryError: Int,
        reclaimSlotBase: Int, reclaimSlotLimit: Int
    ) {
        self.protocolVersion = protocolVersion
        self.modeCount = modeCount
        self.setCount = setCount
        self.stateCount = stateCount
        self.flags = flags
        self.maxPacketSize = maxPacketSize
        self.userSlotLimit = userSlotLimit
        self.factorySlotBase = factorySlotBase
        self.factoryBundleVersion = factoryBundleVersion
        self.factoryManifestCRC = factoryManifestCRC
        self.factoryStatus = factoryStatus
        self.factoryError = factoryError
        self.reclaimSlotBase = reclaimSlotBase
        self.reclaimSlotLimit = reclaimSlotLimit
    }

    public var supportsIdleTaskPicture: Bool {
        stateCount >= 4 && flags & Self.idleTaskPictureFlag != 0
    }

    public var supportsSessionUpload: Bool {
        flags & Self.sessionUploadFlag != 0
    }

    /// 解析 0x99 应答 payload（不含帧头帧尾）。
    /// - 13B 以下、15...21B、23...25B：歧义/截断，fail-closed。
    /// - factory-off 14B：`factorySlotBase=0`（caps14 交叉契约）。
    /// - factory compact 14B：`factorySlotBase=userSlotLimit`，reclaim 取 u16(10)/u16(12)；
    ///   须满足 `userSlotLimit>0`、`reclaimBase>=userSlotLimit`、`reclaimLimit>reclaimBase`，
    ///   否则视为截断 extended，fail-closed。
    ///   不得把缺失的 22B factory 扩展字段猜出来。
    /// - factory 22/26B：维持扩展字段语义。
    public static func parse(_ payload: Data) -> AhaKeyFirmwareCapabilities? {
        let count = payload.count
        guard count == 14 || count == 22 || count >= 26 else { return nil }
        func u16(_ offset: Int) -> UInt16 {
            UInt16(payload[offset]) | (UInt16(payload[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(payload[offset])
                | (UInt32(payload[offset + 1]) << 8)
                | (UInt32(payload[offset + 2]) << 16)
                | (UInt32(payload[offset + 3]) << 24)
        }
        let flags = u16(4)
        let factoryAdvertised = flags & Self.factoryAssetsFlag != 0
        let userSlotLimit = Int(u16(8))
        if factoryAdvertised && count == 14 {
            let reclaimBase = Int(u16(10))
            let reclaimLimit = Int(u16(12))
            // compact 必须能与截断 extended 区分：user>0、reclaimBase>=user、reclaimLimit>reclaimBase。
            guard userSlotLimit > 0,
                  reclaimBase >= userSlotLimit,
                  reclaimLimit > reclaimBase else {
                return nil
            }
            return AhaKeyFirmwareCapabilities(
                protocolVersion: Int(payload[0]),
                modeCount: Int(payload[1]),
                setCount: Int(payload[2]),
                stateCount: Int(payload[3]),
                flags: flags,
                maxPacketSize: Int(u16(6)),
                userSlotLimit: userSlotLimit,
                factorySlotBase: userSlotLimit,
                factoryBundleVersion: 0,
                factoryManifestCRC: 0,
                factoryStatus: 0,
                factoryError: 0,
                reclaimSlotBase: reclaimBase,
                reclaimSlotLimit: reclaimLimit
            )
        }
        let hasExtendedFactoryFields = factoryAdvertised && (count == 22 || count >= 26)
        if factoryAdvertised && !hasExtendedFactoryFields {
            return nil
        }
        return AhaKeyFirmwareCapabilities(
            protocolVersion: Int(payload[0]),
            modeCount: Int(payload[1]),
            setCount: Int(payload[2]),
            stateCount: Int(payload[3]),
            flags: flags,
            maxPacketSize: Int(u16(6)),
            userSlotLimit: userSlotLimit,
            factorySlotBase: hasExtendedFactoryFields ? Int(u16(10)) : 0,
            factoryBundleVersion: hasExtendedFactoryFields ? u32(12) : 0,
            factoryManifestCRC: hasExtendedFactoryFields ? u32(16) : 0,
            factoryStatus: hasExtendedFactoryFields ? Int(payload[20]) : 0,
            factoryError: hasExtendedFactoryFields ? Int(payload[21]) : 0,
            reclaimSlotBase: count >= 26 ? Int(u16(22)) : (hasExtendedFactoryFields ? Int(u16(10)) : 0),
            reclaimSlotLimit: count >= 26 ? Int(u16(24)) : (hasExtendedFactoryFields ? Int(u16(12)) : 0)
        )
    }
}

/// protocolMode 决策矩阵与重试语义（对应 Rhino queryFirmwareCapabilities 的纯逻辑部分）：
/// 最多尝试 maxAttempts 次 0x99；拿到合法能力帧即按 protocolVersion 定 mode；
/// 全部失败则按 firmwareMainVersion 回退 legacy / restrictedUnknown。
public enum AhaKeyProtocolNegotiation {
    /// 0x99 查询最大尝试次数（每次超时 2s，间隔 retryDelayNanoseconds）。
    public static let maxAttempts = 3
    /// 单次查询超时（秒）。
    public static let attemptTimeoutSeconds: Double = 2.0
    /// 两次尝试之间的间隔（纳秒）。
    public static let retryDelayNanoseconds: UInt64 = 250_000_000

    /// 第 failedAttempt 次（1 起计）失败后是否还应重试。
    public static func shouldRetry(afterFailedAttempt failedAttempt: Int) -> Bool {
        failedAttempt < maxAttempts
    }

    /// 拿到合法能力帧：protocolVersion == 3 为 current，其余为 restrictedUnknown。
    public static func mode(forCapabilities capabilities: AhaKeyFirmwareCapabilities) -> AhaKeyProtocolMode {
        capabilities.protocolVersion == 3 ? .current : .restrictedUnknown
    }

    /// 三次全部失败：固件 1.x 再用 0x94 实探任务图能力，避免把“未知命令通用成功空包”误判成可写。
    public static func fallbackMode(
        firmwareMainVersion: Int,
        supportsLegacyTaskPictures: Bool
    ) -> AhaKeyProtocolMode {
        guard firmwareMainVersion == 1 else { return .restrictedUnknown }
        return supportsLegacyTaskPictures ? .legacy : .legacyBaseOnly
    }
}
