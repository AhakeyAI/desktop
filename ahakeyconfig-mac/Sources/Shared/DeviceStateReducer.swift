import Foundation

// MARK: - 设备状态 reducer（阶段 1：状态管理重构地基）
//
// 所有周期性 BLE 状态（完整状态帧、电量、RSSI、连接/断开）的唯一归并入口。
// 纯值类型 + 纯函数：不依赖 @MainActor、不依赖 CoreBluetooth，方便单元测试。
// AhaKeyBLEManager 持有两份快照并调用 `DeviceStateReducer.apply`，
// 仅在快照真实变化时重新赋值（相同快照零发布；一次真实变化最多发布一次）。

/// 核心投影：连接状态与设备身份、电量、工作模式、灯效、拨杆、亮度、固件版本、当前任务图套图。
/// 主 Studio 只观察它；诊断遥测的变化不会触达这份快照。
public struct CoreDeviceSnapshot: Equatable {
    public var isConnected: Bool = false
    public var deviceName: String? = nil
    public var deviceUUID: String = "—"
    public var batteryLevel: Int = 0
    public var firmwareMainVersion: Int = 0
    public var firmwareSubVersion: Int = 0
    public var workMode: Int = 0
    public var lightMode: Int = 0
    public var switchState: Int = 0
    public var brightness: Int = 35
    /// 各 mode 当前激活的任务图套图索引（0x97 或设备状态上报）。
    public var activeTaskPictureSets: [Int: Int] = [:]

    public init() {}
}

/// 诊断投影：RSSI、固件详细信息等遥测。与核心投影隔离，不允许触发主 Studio 刷新。
public struct DeviceDiagnosticsSnapshot: Equatable {
    public var signalStrength: Int = 0
    public var firmwareRevision: String = "—"
    public var modelNumber: String = "—"

    public init() {}
}

/// 归并入口的事件类型。载荷字段对照 `AhaKeyResponseParser.parseDeviceStatus` 实际解析出的字段。
public enum DeviceStateEvent: Equatable {
    /// 完整设备状态响应：电量、固件、工作模式、灯效、拨杆、亮度、当前 mode 的任务图套图。
    /// 注：状态帧里还解析出 `signal`（RSSI），但现有代码从未采用它（RSSI 只走 readRSSI 回调），保持该行为。
    case fullStatus(battery: Int, firmwareMain: Int, firmwareSub: Int, workMode: Int, lightMode: Int, switchState: Int, brightness: Int, activePictureSet: Int)
    /// Battery Service（0x2A19）notify/read 回包。
    case battery(Int)
    /// readRSSI 回调（只在设备信息窗口打开时轮询）。
    case rssi(Int)
    /// Device Information Service 回包（固件修订号 / 型号，连接后各读一次）。nil 表示该项未携带、保留原值。
    case deviceInfo(firmwareRevision: String?, modelNumber: String?)
    /// 0x96 查询 / 0x97 设置回包的当前激活任务图套图。
    case activePictureSet(mode: Int, set: Int)
    /// 连接成功：设备身份（名字/UUID）。
    case connected(name: String?, uuid: String)
    /// 断开：连接状态置为断开、诊断值复位、任务图套图清空（与现有 didDisconnect 行为一致）；
    /// 电量/模式/亮度/固件版本与设备身份保留（现有代码断开时从不清这些）。
    case disconnected
}

/// apply 的副作用说明，由 BLE manager 负责落地（发通知等）。
public enum DeviceStateEffect: Equatable {
    case none
    /// workMode 真实变化（携带新值），manager 据此发一次 `ahaKeyKeyboardWorkModeChanged`。
    case workModeChanged(Int)
}

/// apply 结果：两份新快照 + 副作用。调用方用 Equatable 对比决定是否需要发布。
public struct DeviceStateResult: Equatable {
    public var core: CoreDeviceSnapshot
    public var diagnostics: DeviceDiagnosticsSnapshot
    public var effect: DeviceStateEffect
}

public enum DeviceStateReducer {
    /// 唯一归并入口。字段级"后到的信息覆盖"（last-write-wins）：
    /// 电量同时来自 Battery Service notify（`.battery`）与完整状态帧（`.fullStatus`），后到的覆盖先到的。
    public static func apply(
        _ event: DeviceStateEvent,
        core: CoreDeviceSnapshot,
        diagnostics: DeviceDiagnosticsSnapshot
    ) -> DeviceStateResult {
        var core = core
        var diagnostics = diagnostics
        var effect: DeviceStateEffect = .none

        switch event {
        case let .fullStatus(battery, firmwareMain, firmwareSub, workMode, lightMode, switchState, brightness, activePictureSet):
            core.batteryLevel = battery
            core.firmwareMainVersion = firmwareMain
            core.firmwareSubVersion = firmwareSub
            if core.workMode != workMode {
                core.workMode = workMode
                effect = .workModeChanged(workMode)
            }
            core.lightMode = lightMode
            core.switchState = switchState
            core.brightness = brightness
            core.activeTaskPictureSets[workMode] = activePictureSet

        case let .battery(level):
            core.batteryLevel = level

        case let .rssi(value):
            diagnostics.signalStrength = value

        case let .deviceInfo(firmwareRevision, modelNumber):
            if let firmwareRevision { diagnostics.firmwareRevision = firmwareRevision }
            if let modelNumber { diagnostics.modelNumber = modelNumber }

        case let .activePictureSet(mode, set):
            core.activeTaskPictureSets[mode] = set

        case let .connected(name, uuid):
            core.isConnected = true
            core.deviceName = name
            core.deviceUUID = uuid

        case .disconnected:
            core.isConnected = false
            core.activeTaskPictureSets.removeAll()
            diagnostics.signalStrength = 0

        }

        return DeviceStateResult(core: core, diagnostics: diagnostics, effect: effect)
    }
}
