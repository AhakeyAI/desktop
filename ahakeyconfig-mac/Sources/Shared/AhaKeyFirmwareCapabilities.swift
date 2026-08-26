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

/// 0x99 能力帧解析结果。三档长度变体：
/// - 14 字节：基础字段（无出厂资源信息；factory flag 关闭时 factorySlotBase=0，
///   不得回退为用户槽位上限——WBS-5.7 R2 caps14 交叉契约）；
/// - 22 字节：含出厂资源束信息（factory*，仅 factory flag 打开时可信）；
/// - 26 字节：额外含回收槽位区间（reclaim*）。
public struct AhaKeyFirmwareCapabilities: Equatable {
    public static let idleTaskPictureFlag: UInt16 = 1 << 0
    /// 出厂资源束能力位。打开时必须携带 22 字节扩展字段，否则 parse fail-closed。
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

    /// 解析 0x99 应答 payload（不含帧头帧尾）。长度不足 14 字节返回 nil。
    /// fail-closed 纪律（WBS-5.7 R2 caps14 交叉契约，固件证据 WBS-1 22:51）：
    /// factory flag 打开但帧不足 22 字节 → 返回 nil（不得猜测 factory 布局）；
    /// factory flag 关闭 → factorySlotBase=0（用户槽位从 0 起编，0x95 才不会越界被拒）。
    public static func parse(_ payload: Data) -> AhaKeyFirmwareCapabilities? {
        guard payload.count >= 14 else { return nil }
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
        if factoryAdvertised && payload.count < 22 { return nil }
        let hasExtendedFactoryFields = factoryAdvertised && payload.count >= 22
        return AhaKeyFirmwareCapabilities(
            protocolVersion: Int(payload[0]),
            modeCount: Int(payload[1]),
            setCount: Int(payload[2]),
            stateCount: Int(payload[3]),
            flags: flags,
            maxPacketSize: Int(u16(6)),
            userSlotLimit: Int(u16(8)),
            factorySlotBase: hasExtendedFactoryFields ? Int(u16(10)) : 0,
            factoryBundleVersion: hasExtendedFactoryFields ? u32(12) : 0,
            factoryManifestCRC: hasExtendedFactoryFields ? u32(16) : 0,
            factoryStatus: hasExtendedFactoryFields ? Int(payload[20]) : 0,
            factoryError: hasExtendedFactoryFields ? Int(payload[21]) : 0,
            reclaimSlotBase: payload.count >= 26 ? Int(u16(22)) : (hasExtendedFactoryFields ? Int(u16(10)) : 0),
            reclaimSlotLimit: payload.count >= 26 ? Int(u16(24)) : (hasExtendedFactoryFields ? Int(u16(12)) : 0)
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
