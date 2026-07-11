import Foundation

/// Gen2 BLE 协议扩展（占位；固件联调后替换 payload 编解码）。
enum AhaKeyCommandV2 {
    static let cmdMagneticModuleNotify: UInt8 = 0x95
    static let cmdIMUData: UInt8 = 0x96
    static let cmdOceanLightPreset: UInt8 = 0x97
    static let cmdOceanLightMarquee: UInt8 = 0x98

    static func setOceanLightPreset(_ config: OceanLightConfig) -> Data {
        let preset = UInt8(clamping: config.selectedPresetId)
        let brightness = UInt8(clamping: Int(config.brightness * 255))
        let flags: UInt8 = (config.imuEnabled ? 0x01 : 0x00) | (config.powerSwitchEnabled ? 0x02 : 0x00)
        return Data(AhaKeyCommand.header + [cmdOceanLightPreset, preset, brightness, flags] + AhaKeyCommand.trailer)
    }

    static func setMarqueeText(_ text: String) -> Data {
        let bytes = Array(text.utf8.prefix(48))
        return Data(AhaKeyCommand.header + [cmdOceanLightMarquee] + bytes + AhaKeyCommand.trailer)
    }
}
