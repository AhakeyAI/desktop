import SwiftUI

struct OceanLightPreset: Identifiable, Equatable {
    let id: Int
    let name: String
    let previewColors: [Color]
    let animationKind: OceanLightAnimationKind

    static let all: [OceanLightPreset] = [
        OceanLightPreset(id: 1, name: "深海静流", previewColors: [.cyan, .blue, .teal], animationKind: .flow),
        OceanLightPreset(id: 2, name: "珊瑚脉冲", previewColors: [.orange, .pink, .red], animationKind: .pulse),
        OceanLightPreset(id: 3, name: "极光带", previewColors: [.green, .purple, .blue], animationKind: .wave),
        OceanLightPreset(id: 4, name: "生物荧光", previewColors: [.mint, .cyan, .yellow], animationKind: .sparkle),
        OceanLightPreset(id: 5, name: "日落潮汐", previewColors: [.orange, .red, .pink], animationKind: .flow),
        OceanLightPreset(id: 6, name: "冰洋", previewColors: [.white, .cyan, .blue], animationKind: .wave),
        OceanLightPreset(id: 7, name: "熔岩海", previewColors: [.red, .orange, .yellow], animationKind: .flow),
        OceanLightPreset(id: 8, name: "星云", previewColors: [.purple, .pink, .indigo], animationKind: .sparkle),
        OceanLightPreset(id: 9, name: "翡翠池", previewColors: [.green, .mint, .teal], animationKind: .pulse),
        OceanLightPreset(id: 10, name: "自定义", previewColors: [.gray, .white, .gray], animationKind: .wave),
    ]

    static func preset(id: Int) -> OceanLightPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

enum OceanLightAnimationKind: String, Codable {
    case flow
    case pulse
    case wave
    case sparkle
}

struct OceanLightConfig: Equatable, Codable {
    var selectedPresetId: Int
    var brightness: Double
    var marqueeText: String
    var imuEnabled: Bool
    var powerSwitchEnabled: Bool

    static let `default` = OceanLightConfig(
        selectedPresetId: 1,
        brightness: 0.85,
        marqueeText: "",
        imuEnabled: true,
        powerSwitchEnabled: true
    )

    var selectedPreset: OceanLightPreset {
        OceanLightPreset.preset(id: selectedPresetId)
    }
}

enum OceanLightConfigStore {
    static func load() -> OceanLightConfig {
        guard let data = UserDefaults.standard.data(forKey: DeviceCapabilityStorage.oceanLightConfigKey),
              let config = try? JSONDecoder().decode(OceanLightConfig.self, from: data) else {
            return .default
        }
        return config
    }

    static func save(_ config: OceanLightConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: DeviceCapabilityStorage.oceanLightConfigKey)
    }
}
