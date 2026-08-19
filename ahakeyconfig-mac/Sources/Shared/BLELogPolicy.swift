import Foundation

// MARK: - 三级日志策略（阶段 2：日志分级）
//
// 1. 默认永久级（常开）：连接/断开/重连状态转换、设备状态真实变化、命令失败/协议错误。
//    进内存日志、os_log、诊断文件 ble-comm.log。
// 2. 内存诊断级：默认级全部内容 + 一次性运行信息（扫描、特征就绪、用户发起的写操作等）。
//    进内存日志（BLELogStore）与 os_log，不写 ble-comm.log。
// 3. 临时详细级（默认关闭）：周期 TX/RX 流量（→ CMD、← DATA/NOTIFY、写入完成、每轮状态原文、
//    空转轮询）。只在详细会话开启时写 ble-verbose.log，不进内存、不进默认文件。

/// 日志类别。每条日志在生产点归类，路由决策见 `BLELogRouting`。
public enum BLELogCategory: Sendable {
    /// 连接生命周期：已连接/已断开/连接失败/用户主动断开/蓝牙开关。
    case lifecycle
    /// 设备状态真实变化（reducer 快照 diff 摘要，一条）。
    case stateChange
    /// 命令失败、协议错误、写失败、超时等错误路径。
    case error
    /// 一次性运行信息：扫描/发现设备/服务特征就绪/用户发起的写操作/上传里程碑等。
    case diagnostic
    /// 周期 TX/RX 流量：→ CMD、← DATA/NOTIFY、写入完成、每轮状态原文、后台空转轮询。
    case verbose

    /// 该类别日志的去向。
    public var routing: BLELogRouting {
        switch self {
        case .lifecycle, .stateChange, .error:
            // 默认永久级
            return BLELogRouting(
                entersMemoryStore: true,
                entersSystemLog: true,
                entersPersistentLog: true,
                requiresVerboseSession: false
            )
        case .diagnostic:
            // 内存诊断级
            return BLELogRouting(
                entersMemoryStore: true,
                entersSystemLog: true,
                entersPersistentLog: false,
                requiresVerboseSession: false
            )
        case .verbose:
            // 临时详细级：仅详细会话开启时写 ble-verbose.log
            return BLELogRouting(
                entersMemoryStore: false,
                entersSystemLog: false,
                entersPersistentLog: false,
                requiresVerboseSession: true
            )
        }
    }
}

/// 一条日志的落点决策。
public struct BLELogRouting: Equatable, Sendable {
    /// 进内存日志（BLELogStore，内存诊断级）。
    public var entersMemoryStore: Bool
    /// 进 os_log。
    public var entersSystemLog: Bool
    /// 写诊断文件 ble-comm.log（默认永久级）。
    public var entersPersistentLog: Bool
    /// 仅详细会话开启时写 ble-verbose.log（周期 TX/RX）。
    public var requiresVerboseSession: Bool

    public init(
        entersMemoryStore: Bool,
        entersSystemLog: Bool,
        entersPersistentLog: Bool,
        requiresVerboseSession: Bool
    ) {
        self.entersMemoryStore = entersMemoryStore
        self.entersSystemLog = entersSystemLog
        self.entersPersistentLog = entersPersistentLog
        self.requiresVerboseSession = requiresVerboseSession
    }
}
