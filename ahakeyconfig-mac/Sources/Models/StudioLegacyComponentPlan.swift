import Foundation
import AhaKeyConfigShared

/// Legacy ACK-only transport still obeys the same component boundary. An ACK
/// is not a readback or power-loss persistence proof.
struct StudioLegacyComponentPlan {
    let deviceID: String?
    let mode: AhaKeyModeSlot
    let part: AhaKeyStudioPart
    let submitted: AhaKeyModeDraft
    let commands: [(data: Data, label: String)]
    let uploadsArtwork: Bool

    enum Failure: Error, LocalizedError {
        case unsupported, invalidKey, missingArtwork
        case transportLimit(Int)
        var errorDescription: String? {
            switch self {
            case .unsupported: return NSLocalizedString("旧固件不支持此组件的确认写入，本次未修改键盘。", comment: "")
            case .invalidKey: return NSLocalizedString("当前按键无法安全写入，请检查快捷键、宏释放和英文描述。", comment: "")
            case .missingArtwork: return NSLocalizedString("请先为当前模式选择图片或 GIF。", comment: "")
            case .transportLimit(let maximum): return String(format: NSLocalizedString("当前连接最多发送 %d 字节，请缩短按键描述或宏后重试。本次未写入。", comment: ""), maximum)
            }
        }
    }
    init(mode: AhaKeyModeSlot, part: AhaKeyStudioPart, submitted: AhaKeyModeDraft, deviceID: String? = nil) throws {
        self.deviceID = deviceID
        guard submitted.mode == mode else { throw Failure.unsupported }
        self.mode = mode; self.part = part; self.submitted = submitted
        let modeByte = UInt8(mode.rawValue)
        var commands: [(data: Data, label: String)] = []
        if let role = part.keyRole {
            let key = submitted.key(for: role), index = UInt8(role.rawValue)
            guard key.voicePreset != .systemDictation else { throw Failure.unsupported }
            guard let description = key.description.data(using: .ascii), description.count <= 20,
                  description.allSatisfy({ (0x20...0x7E).contains($0) }) else { throw Failure.invalidKey }
            let payload = key.usesMacro ? key.macro.flattenedBytes : key.shortcut.hidCodes
            guard payload.count <= 98,
                  (payload.isEmpty && !key.usesMacro) || SideSwitchBindingConfiguration.validAction(
                    Data([key.usesMacro ? 0x74 : 0x73, UInt8(payload.count)]) + Data(payload), maximumBytes: 100)
            else { throw Failure.invalidKey }
            if role == .voice { _ = try StudioKeyWriteProposal.make(key: key, mode: mode) }
            if key.usesMacro {
                commands.append((AhaKeyCommand.setKeyMapping(mode: modeByte, keyIndex: index, hidCodes: []), "Clear shortcut layer"))
                commands.append((AhaKeyCommand.setKeyMacro(mode: modeByte, keyIndex: index, macroData: payload), "Write selected macro"))
            } else {
                commands.append((AhaKeyCommand.setKeyMacro(mode: modeByte, keyIndex: index, macroData: []), "Clear macro layer"))
                commands.append((AhaKeyCommand.setKeyMapping(mode: modeByte, keyIndex: index, hidCodes: payload), "Write selected shortcut"))
            }
            commands.append((AhaKeyCommand.setKeyDescription(mode: modeByte, keyIndex: index, text: key.description), "Write selected description"))
            uploadsArtwork = false
        } else {
            switch part {
            case .lightBar:
                let light = submitted.lightBar
                guard (1...100).contains(light.brightness) else { throw Failure.unsupported }
                commands.append((AhaKeyCommand.setLightMapping(mode: modeByte,
                    stateEffects: IDEState.allCases.map { light.effect(for: $0).firmwareIndex }), "Write selected light mapping"))
                commands.append((AhaKeyCommand.setBrightness(UInt8(light.brightness)), "Write global brightness"))
                uploadsArtwork = false
            case .oledDisplay:
                guard submitted.oled.localAssetPath != nil else { throw Failure.missingArtwork }
                uploadsArtwork = true
            default: throw Failure.unsupported
            }
        }
        commands.append((AhaKeyCommand.saveConfig(), "Save selected component"))
        self.commands = commands
    }
    func validateTransport(maximum: Int) throws {
        guard maximum > 0, commands.allSatisfy({ $0.data.count <= maximum }) else { throw Failure.transportLimit(maximum) }
    }
    static func reconcilingOLED(current: AhaKeyOLEDDraft, submitted: AhaKeyOLEDDraft,
                                confirmed: AhaKeyOLEDDraft) -> AhaKeyOLEDDraft {
        if current.localAssetPath == submitted.localAssetPath && current.framesPerSecond == submitted.framesPerSecond {
            return confirmed
        }
        var pending = current; pending.needsDeviceUpload = true
        return pending
    }
    func persistExistingBaseline(_ baseline: AhaKeyStudioDraft, confirmedOLED: AhaKeyOLEDDraft? = nil,
                                 defaults: UserDefaults = .standard) -> AhaKeyStudioDraft {
        // A partial acknowledgment must not manufacture a whole-device
        // baseline for an installation that has never confirmed one.
        if let persisted = AhaKeyStudioStore.loadSynced(from: defaults) {
            AhaKeyStudioStore.saveSynced(updatingBaseline(persisted, confirmedOLED: confirmedOLED), to: defaults)
        }
        return updatingBaseline(baseline, confirmedOLED: confirmedOLED)
    }
    func updatingBaseline(_ baseline: AhaKeyStudioDraft, confirmedOLED: AhaKeyOLEDDraft? = nil) -> AhaKeyStudioDraft {
        var result = baseline, updated = baseline.draft(for: mode)
        if let role = part.keyRole { updated.updateKey(submitted.key(for: role)) }
        else if part == .oledDisplay { updated.oled = confirmedOLED ?? submitted.oled }
        else if part == .lightBar { updated.lightBar = submitted.lightBar }
        result.updateMode(updated)
        if part == .lightBar {
            for slot in AhaKeyModeSlot.allCases {
                var global = result.draft(for: slot)
                global.lightBar.brightness = submitted.lightBar.brightness
                result.updateMode(global)
            }
        }
        return result
    }
}
