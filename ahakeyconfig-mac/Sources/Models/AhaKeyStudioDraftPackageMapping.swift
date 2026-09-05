import AhaKeyConfigShared
import CryptoKit
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

/// 本地素材元数据探测：帧数、首帧像素尺寸与内容身份（digest/byteCount/mediaType）。
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

    static func contentIdentity(
        at url: URL?
    ) -> (sha256: AhaKeySHA256Digest, byteCount: UInt64, mediaType: AhaKeyMediaType)? {
        guard let url,
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let sha256 = try? AhaKeySHA256Digest(
                SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
              ),
              let mediaType = try? AhaKeyMediaType(mediaType(for: url)) else {
            return nil
        }
        return (sha256, UInt64(data.count), mediaType)
    }

    private static func mediaType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "gif":
            return "gif"
        case "png":
            return "png"
        case "jpg", "jpeg":
            return "jpeg"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - C2R1：单页冻结快照（纯映射，不组包）

extension AhaKeyStudioDraft {
    /// 只冻结 `pageID` 上的字段。其它页即使 dirty 也不会进入快照。
    /// 设备权威 baseline 必须经 `fieldAuthorities` 传入；`lastSyncedDraft` 只做用户 dirty 比较，缺失不得 fallback 到 `self`。
    func frozenPageSnapshot(
        pageID: AhaKeyStudioPageID,
        lastSyncedDraft: AhaKeyStudioDraft?,
        fieldAuthorities: [AhaKeyStudioFieldID: AhaKeyStudioFieldAuthority] = [:],
        profile: AhaKeyOLEDCompatibilityProfile,
        selectedTaskSet: Int? = nil,
        overwriteConfirmed: Bool = false
    ) -> AhaKeyStudioPageSnapshot {
        let currentFields = ownedFields(on: pageID)
        let cachedFields: [AhaKeyStudioFieldID: AhaKeyStudioFieldValue]
        if let lastSyncedDraft {
            cachedFields = Dictionary(
                uniqueKeysWithValues: lastSyncedDraft.ownedFields(on: pageID).map { ($0.id, $0.value) }
            )
        } else {
            cachedFields = [:]
        }
        let frozen = currentFields.map { field -> AhaKeyStudioFrozenField in
            let authority = fieldAuthorities[field.id] ?? .unknown
            let baseline = authority.resolvedBaseline()
            let userDirty: Bool
            if lastSyncedDraft == nil {
                userDirty = true
            } else {
                userDirty = cachedFields[field.id] != field.value
            }
            return AhaKeyStudioFrozenField(
                id: field.id,
                value: field.value,
                isDirty: userDirty,
                baseline: baseline
            )
        }
        let selected: Int
        if case .screen(let slot) = pageID {
            selected = selectedTaskSet ?? modeDraft(slot: slot)?.oled.activeGIFSet ?? 0
        } else {
            selected = selectedTaskSet ?? 0
        }
        return AhaKeyStudioPageSnapshot(
            pageID: pageID,
            profile: profile,
            selectedTaskSet: selected,
            overwriteConfirmed: overwriteConfirmed,
            fields: frozen
        )
    }

    /// 字段清单由 Shared ownership 驱动；本层只按 field ID 取值。
    fileprivate func ownedFields(on pageID: AhaKeyStudioPageID) -> [(id: AhaKeyStudioFieldID, value: AhaKeyStudioFieldValue)] {
        AhaKeyStudioFieldOwnership.fieldIDs(on: pageID).compactMap { id in
            guard let value = value(for: id) else { return nil }
            return (id, value)
        }
    }

    fileprivate func value(for id: AhaKeyStudioFieldID) -> AhaKeyStudioFieldValue? {
        switch id {
        case .keyAction(let slot, let role):
            return keyDraft(slot: slot, role: role).map { .keyAction($0.packageInput().action) }
        case .keyDescription(let slot, let role):
            return keyDraft(slot: slot, role: role).map { .text($0.description) }
        case .keyVoicePreset(let slot, let role):
            return keyDraft(slot: slot, role: role).map { .optionalText($0.voicePreset?.rawValue) }
        case .lightBrightness(let slot):
            return modeDraft(slot: slot).map { .integer($0.lightBar.brightness) }
        case .lightMapping(let slot, let state):
            guard let mapping = modeDraft(slot: slot)?.lightBar.stateMappings.first(where: {
                $0.state.rawValue == state
            }) else { return nil }
            return .text(mapping.effect.rawValue)
        case .screenStatusLine(let slot):
            return modeDraft(slot: slot).map { .text($0.oled.statusLine) }
        case .screenFramesPerSecond(let slot):
            return modeDraft(slot: slot).map { .integer($0.oled.framesPerSecond) }
        case .screenActiveSet(let slot):
            return modeDraft(slot: slot).map { .integer($0.oled.activeGIFSet) }
        case .screenTaskAsset(let slot, let setIndex, let state):
            guard let mode = modeDraft(slot: slot),
                  mode.oled.taskGIFSets.indices.contains(setIndex) else { return nil }
            guard let asset = mode.oled.taskGIFSets[setIndex].assets.first(where: {
                $0.state.rawValue == Int(state.rawValue)
            }) else { return nil }
            let metadata = AhaKeyStudioAssetMetadataProbe.probe(asset.localAssetPath)
            let identity = AhaKeyStudioAssetMetadataProbe.contentIdentity(at: metadata.url)
            return .asset(
                path: asset.localAssetPath,
                framesPerSecond: asset.framesPerSecond,
                declaredFrameCount: metadata.frameCount,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                sha256: identity?.sha256,
                byteCount: identity?.byteCount,
                mediaType: identity?.mediaType
            )
        case .leverMacro, .powerAction:
            return nil
        }
    }

    fileprivate func modeDraft(slot: UInt8) -> AhaKeyModeDraft? {
        modes.first { $0.mode.rawValue == Int(slot) }
    }

    fileprivate func keyDraft(slot: UInt8, role: AhaKeyDesiredConfiguration.KeyRole) -> AhaKeyKeyDraft? {
        modeDraft(slot: slot)?.keys.first { $0.role.rawValue == Int(role.rawValue) }
    }
}
