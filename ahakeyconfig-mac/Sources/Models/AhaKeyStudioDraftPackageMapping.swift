import AhaKeyConfigShared
import Foundation
import ImageIO

// MARK: - WBS 5.7 切片 2：Studio draft → 组装器输入的薄映射
//
// 本层只做字段搬运 + 本地文件元数据探测（帧数/宽高），不含校验逻辑——
// 构造校验在 Shared 层 `AhaKeyStudioPackageAssembler`，受理校验在 Runtime。
// `taskGIFSchemaVersion` 是设备同步追踪字段，不进 canonical 包；`activeGIFSet` 透传
// （-1 = 尚未同步基线，跨重启保留）。

extension AhaKeyStudioDraft {
    /// draft → facade apply 输入（模式按槽位升序）。
    func packageModeInputs() -> [AhaKeyStudioModeInput] {
        modes.sorted { $0.mode.rawValue < $1.mode.rawValue }.map { $0.packageInput() }
    }
}

extension AhaKeyModeDraft {
    func packageInput() -> AhaKeyStudioModeInput {
        AhaKeyStudioModeInput(
            slot: UInt8(mode.rawValue),
            keys: keys.map { $0.packageInput() },
            oled: oled.packageInput(),
            lightBar: lightBar.packageInput()
        )
    }
}

extension AhaKeyKeyDraft {
    func packageInput() -> AhaKeyStudioKeyInput {
        // MacroAction/ShortcutModifier 的 raw 域已被各自枚举约束合法，force-try 不会触发。
        let action: AhaKeyDesiredConfiguration.KeyAction
        if macro.isEmpty {
            action = .shortcut(try! AhaKeyDesiredConfiguration.Shortcut(
                modifiers: shortcut.orderedModifiers.map(\.rawValue),
                keyCode: shortcut.keyCode
            ))
        } else {
            action = .macro(macro.map {
                try! AhaKeyDesiredConfiguration.MacroStep(action: $0.action.rawValue, param: $0.param)
            })
        }
        return AhaKeyStudioKeyInput(
            // AhaKeyKeyRole 与 KeyRole 的 rawValue 域一致（0...3）。
            role: AhaKeyDesiredConfiguration.KeyRole(rawValue: UInt8(role.rawValue))!,
            action: action,
            description: description,
            voicePreset: voicePreset?.rawValue
        )
    }
}

extension AhaKeyOLEDDraft {
    func packageInput() -> AhaKeyStudioOLEDInput {
        AhaKeyStudioOLEDInput(
            statusLine: statusLine,
            framesPerSecond: framesPerSecond,
            taskSets: taskGIFSets.prefix(2).map { $0.packageInput() },
            activeSet: activeGIFSet
        )
    }
}

extension AhaKeyTaskGIFSetDraft {
    func packageInput() -> AhaKeyStudioTaskSetInput {
        AhaKeyStudioTaskSetInput(assets: assets.map { $0.packageInput() })
    }
}

extension AhaKeyTaskGIFAssetDraft {
    func packageInput() -> AhaKeyStudioTaskAssetInput {
        let metadata = AhaKeyStudioAssetMetadataProbe.probe(localAssetPath)
        return AhaKeyStudioTaskAssetInput(
            state: AhaKeyDesiredConfiguration.TaskDisplayState(rawValue: UInt8(state.rawValue))!,
            localFileURL: metadata.url,
            framesPerSecond: framesPerSecond,
            declaredFrameCount: metadata.frameCount,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight
        )
    }
}

extension AhaKeyLightBarDraft {
    func packageInput() -> AhaKeyStudioLightBarInput {
        AhaKeyStudioLightBarInput(
            stateMappings: stateMappings.map {
                AhaKeyStudioLightMappingInput(state: $0.state.rawValue, effect: $0.effect.rawValue)
            },
            brightness: brightness
        )
    }
}

/// 本地素材元数据探测：帧数与首帧像素尺寸（供申报元数据；facade ingest 前复核实际值）。
enum AhaKeyStudioAssetMetadataProbe {
    static func probe(_ path: String?) -> (url: URL?, frameCount: Int?, pixelWidth: Int?, pixelHeight: Int?) {
        guard let path, !path.isEmpty else { return (nil, nil, nil, nil) }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return (url, nil, nil, nil)
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0,
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return (url, nil, nil, nil)
        }
        return (url, frameCount, first.width, first.height)
    }
}
