import Foundation

/// 设备代际；开发阶段通过 Dev Toggle 切换，后续改为读取 Model Number / 固件版本。
enum DeviceGeneration: String, CaseIterable, Identifiable, Codable {
    case x1
    case gen2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .x1: return "X1"
        case .gen2: return "Gen2"
        }
    }

    var supportsMagneticPort: Bool { self == .gen2 }
    var supportsOceanLight: Bool { self == .gen2 }
    var modeSlotCount: Int { self == .gen2 ? 4 : 3 }
}

enum DeviceCapabilityStorage {
    static let previewGenerationKey = "AhaKey.Dev.PreviewGeneration"
    static let magneticModuleKey = "AhaKey.Gen2.MagneticModule"
    static let magneticModuleUnlockKey = "AhaKey.Gen2.MagneticModuleUnlocks"
    static let oceanLightConfigKey = "AhaKey.Gen2.OceanLightConfig"
}
