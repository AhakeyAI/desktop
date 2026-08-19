import Foundation

/// AhaKey-X1 BLE 协议编解码
///
/// 帧格式: AA BB [cmd:1] [data:N] CC DD
/// 原厂代码: build_device_frame(cmd, data) = FRAME_HEAD + bytes([cmd]) + data + FRAME_TAIL
enum AhaKeyCommand {
    static let header: [UInt8] = [0xAA, 0xBB]
    static let trailer: [UInt8] = [0xCC, 0xDD]
    static let oledWidth = 160
    static let oledHeight = 80
    static let oledFrameSlotSize = 28_672
    static let oledFactoryReservedSlots = 10
    static let oledModeCount = 4
    static let oledMaxFramesPerMode = 70
    static let oledMaxFrames = oledMaxFramesPerMode
    /// 任务状态资源单张上限（超出时均匀抽帧）。
    static let taskOLEDMaxFrames = 30
    /// 用户选择的 GIF 源文件大小上限（避免过大文件拖慢解码与 BLE 上传）。
    static let oledMaxSourceFileBytes = 2 * 1024 * 1024 // 2 MB
    /// 固件端要求每个 prepareWrite 的 address 必须 4096 字节对齐（flash 扇区大小）。
    /// 原厂 Python 客户端也用 4096 作为写入分块大小，一次 prepareWrite 刚好擦写一个扇区。
    static let oledChunkSize = 4096
    /// BLE data 特征单次 writeValue 的软上限（与固件接收 FIFO 匹配，不走协商 MTU）。
    static let oledPacketSize = 180

    // 设备命令 (DeviceCmd)
    static let cmdChangeName: UInt8 = 0x01
    static let cmdChangeAppearance: UInt8 = 0x02
    static let cmdSaveConfig: UInt8 = 0x04
    static let cmdUpdateCustomKey: UInt8 = 0x73
    static let cmdPrepareWrite: UInt8 = 0x80
    static let cmdWriteResult: UInt8 = 0x81
    static let cmdUpdatePic: UInt8 = 0x82
    static let cmdReadPicState: UInt8 = 0x83
    static let cmdUpdateState: UInt8 = 0x90  // IDE 状态 → LED 变色

    // 以下命令码与 CH582 最新固件对齐（APP/sub_main/command_solve.c）
    static let cmdSetLightMapping: UInt8 = 0x84   // per-mode per-state LED 映射
    static let cmdSetBrightness: UInt8 = 0x85     // 全局 WS2812 亮度 1-100
    static let cmdPreviewLightEffect: UInt8 = 0x91 // 直接预览某个灯效，不保存配置
    static let cmdSetWorkMode: UInt8 = 0x92       // 远程切换工作模式 0-3

    // AI OLED 任务状态资源：Working=1, Waiting=2, Done=3。
    static let cmdUpdateTaskPic: UInt8 = 0x93
    static let cmdReadTaskPicState: UInt8 = 0x94
    static let cmdUpdateTaskPicSet: UInt8 = 0x95
    static let cmdReadTaskPicSet: UInt8 = 0x96
    static let cmdSetActiveTaskPicSet: UInt8 = 0x97
    /// 结束任务图数据写入，但不替换普通每模式动画绑定。
    static let cmdFinishTaskPicWrite: UInt8 = 0x98
    /// 固件能力查询（M1d：协商 protocolMode，解析逻辑在 AhaKeyConfigShared 的 AhaKeyFirmwareCapabilities）。
    static let cmdCapabilities: UInt8 = 0x99

    static func oledStartIndex(forMode mode: UInt8) -> UInt16 {
        UInt16(oledFactoryReservedSlots + Int(min(3, mode)) * oledMaxFramesPerMode)
    }

    // 按键子类型 (KeySubType)
    static let subShortcut: UInt8 = 0x73
    static let subMacro: UInt8 = 0x74
    static let subDescription: UInt8 = 0x75

    /// 设备状态查询 → AA BB 00 CC DD
    static func queryDeviceStatus() -> Data {
        Data(header + [0x00] + trailer)
    }

    /// 保存配置到设备 Flash → AA BB 04 CC DD
    static func saveConfig() -> Data {
        Data(header + [cmdSaveConfig] + trailer)
    }

    /// 键码写入 → AA BB 73 73 [mode] [key_index] [hid_codes...] CC DD
    /// - Parameters:
    ///   - mode: 工作模式 0-3
    ///   - keyIndex: 0=Key1, 1=Key2, 2=Key3, 3=Key4
    ///   - hidCodes: HID Usage ID 数组（修饰键在前，普通键在后，最多 98 字节）
    static func setKeyMapping(mode: UInt8 = 0, keyIndex: UInt8, hidCodes: [UInt8]) -> Data {
        let payload: [UInt8] = [subShortcut, mode, keyIndex] + hidCodes
        return Data(header + [cmdUpdateCustomKey] + payload + trailer)
    }

    /// 描述写入 → AA BB 73 75 [mode] [key_index] [utf8...] CC DD
    /// - Parameters:
    ///   - mode: 工作模式 0-3
    ///   - keyIndex: 0=Key1, 1=Key2, 2=Key3, 3=Key4
    ///   - text: 显示在 LCD 上的按键描述（最多 20 字节 ASCII）
    static func setKeyDescription(mode: UInt8 = 0, keyIndex: UInt8, text: String) -> Data {
        let textBytes = Array(text.sanitizedASCII(maxLength: 20).utf8)
        let payload: [UInt8] = [subDescription, mode, keyIndex] + textBytes
        return Data(header + [cmdUpdateCustomKey] + payload + trailer)
    }

    /// 宏写入 → AA BB 73 74 [mode] [key_index] [action, param, ...] CC DD
    static func setKeyMacro(mode: UInt8 = 0, keyIndex: UInt8, macroData: [UInt8]) -> Data {
        let payload: [UInt8] = [subMacro, mode, keyIndex] + macroData
        return Data(header + [cmdUpdateCustomKey] + payload + trailer)
    }

    /// 修改设备名称 → AA BB 01 [utf8...] CC DD
    static func changeName(_ name: String) -> Data {
        let nameBytes = Array(name.utf8.prefix(21))
        return Data(header + [cmdChangeName] + nameBytes + trailer)
    }

    /// 修改 BLE Appearance → AA BB 02 [appearance] CC DD
    static func changeAppearance(_ value: UInt8) -> Data {
        Data(header + [cmdChangeAppearance, value] + trailer)
    }

    /// 读取图片状态 → AA BB 83 [mode] CC DD
    static func readPicState(mode: UInt8) -> Data {
        Data(header + [cmdReadPicState, mode] + trailer)
    }

    /// 预备写入大块数据 → AA BB 80 [flag:1] [chunk_len:2 LE] [address:4 LE] CC DD
    static func prepareWrite(flag: UInt8 = 0x00, chunkLength: Int, address: UInt32) -> Data {
        let payload: [UInt8] = [
            flag,
            UInt8(chunkLength & 0xFF),
            UInt8((chunkLength >> 8) & 0xFF),
            UInt8(address & 0xFF),
            UInt8((address >> 8) & 0xFF),
            UInt8((address >> 16) & 0xFF),
            UInt8((address >> 24) & 0xFF),
        ]
        return Data(header + [cmdPrepareWrite] + payload + trailer)
    }

    /// 更新 LCD 动画参数 → AA BB 82 [mode] [start_index:2 LE] [frame_count:2 LE] [time_delay:2 LE] CC DD
    static func updatePicture(mode: UInt8, startIndex: UInt16, frameCount: UInt16, timeDelayMs: UInt16) -> Data {
        let payload: [UInt8] = [
            mode,
            UInt8(startIndex & 0xFF),
            UInt8((startIndex >> 8) & 0xFF),
            UInt8(frameCount & 0xFF),
            UInt8((frameCount >> 8) & 0xFF),
            UInt8(timeDelayMs & 0xFF),
            UInt8((timeDelayMs >> 8) & 0xFF),
        ]
        return Data(header + [cmdUpdatePic] + payload + trailer)
    }

    /// AI OLED 元数据：mode, state, flash 帧范围与帧间隔。
    static func updateTaskPicture(mode: UInt8, state: UInt8, startIndex: UInt16, frameCount: UInt16, timeDelayMs: UInt16) -> Data {
        let payload: [UInt8] = [
            mode, state,
            UInt8(startIndex & 0xFF), UInt8((startIndex >> 8) & 0xFF),
            UInt8(frameCount & 0xFF), UInt8((frameCount >> 8) & 0xFF),
            UInt8(timeDelayMs & 0xFF), UInt8((timeDelayMs >> 8) & 0xFF),
        ]
        return Data(header + [cmdUpdateTaskPic] + payload + trailer)
    }

    static func readTaskPictureState(mode: UInt8, state: UInt8) -> Data {
        Data(header + [cmdReadTaskPicState, mode, state] + trailer)
    }

    static func updateTaskPictureSet(mode: UInt8, set: UInt8, state: UInt8, startIndex: UInt16, frameCount: UInt16, timeDelayMs: UInt16) -> Data {
        let payload: [UInt8] = [
            mode, set, state,
            UInt8(startIndex & 0xFF), UInt8((startIndex >> 8) & 0xFF),
            UInt8(frameCount & 0xFF), UInt8((frameCount >> 8) & 0xFF),
            UInt8(timeDelayMs & 0xFF), UInt8((timeDelayMs >> 8) & 0xFF),
        ]
        return Data(header + [cmdUpdateTaskPicSet] + payload + trailer)
    }

    static func readTaskPictureSet(mode: UInt8, set: UInt8, state: UInt8) -> Data {
        Data(header + [cmdReadTaskPicSet, mode, set, state] + trailer)
    }

    static func setActiveTaskPictureSet(mode: UInt8, set: UInt8) -> Data {
        Data(header + [cmdSetActiveTaskPicSet, mode, set] + trailer)
    }

    static func finishTaskPictureWrite() -> Data {
        Data(header + [cmdFinishTaskPicWrite] + trailer)
    }

    /// 固件能力查询 → AA BB 99 CC DD
    static func queryCapabilities() -> Data {
        Data(header + [cmdCapabilities] + trailer)
    }

    /// IDE 状态同步 → AA BB 90 [state] CC DD
    /// 驱动键盘 LED 变色，反映 Claude/Cursor 当前状态
    static func updateState(_ state: IDEState) -> Data {
        Data(header + [cmdUpdateState, state.rawValue] + trailer)
    }

    /// per-mode per-state LED 灯效映射 → AA BB 84 [mode] [state0_light]...[stateN_light] CC DD
    /// 长度必须等于 2 + CL_STATE_COUNT（与固件 `command_solve.c` 一致）
    static func setLightMapping(mode: UInt8, stateEffects: [UInt8]) -> Data {
        let stateCount = IDEState.allCases.count
        var effects = Array(stateEffects.prefix(stateCount))
        while effects.count < stateCount { effects.append(LightEffectStyle.off.firmwareIndex) }
        return Data(header + [cmdSetLightMapping, mode] + effects + trailer)
    }

    /// 全局 WS2812 亮度 → AA BB 85 [brightness] CC DD
    static func setBrightness(_ value: UInt8) -> Data {
        let clamped = max(1, min(100, value))
        return Data(header + [cmdSetBrightness, clamped] + trailer)
    }

    /// 直接预览某个灯效 → AA BB 91 [effect] CC DD
    static func previewLightEffect(_ effect: UInt8) -> Data {
        Data(header + [cmdPreviewLightEffect, effect] + trailer)
    }

    /// 切换工作模式 → AA BB 92 [mode] CC DD
    static func setWorkMode(_ mode: UInt8) -> Data {
        Data(header + [cmdSetWorkMode, min(3, mode)] + trailer)
    }
}

/// IDE 状态枚举（原厂 ClaudeState）
/// 发送到键盘后驱动 LED 颜色变化
enum IDEState: UInt8, CaseIterable, Codable, Identifiable {
    case notification = 0        // 通知
    case permissionRequest = 1   // 等待授权
    case postToolUse = 2         // 工具执行完毕
    case preToolUse = 3          // 工具执行中
    case sessionStart = 4        // 会话开始
    case stop = 5                // 已停止
    case taskCompleted = 6       // 任务完成
    case userPromptSubmit = 7    // 用户提交
    case sessionEnd = 8          // 会话结束

    var label: String {
        switch self {
        case .notification: return NSLocalizedString("0 通知", comment: "")
        case .permissionRequest: return NSLocalizedString("1 等待授权", comment: "")
        case .postToolUse: return NSLocalizedString("2 工具完毕", comment: "")
        case .preToolUse: return NSLocalizedString("3 工具执行", comment: "")
        case .sessionStart: return NSLocalizedString("4 会话开始", comment: "")
        case .stop: return NSLocalizedString("5 停止", comment: "")
        case .taskCompleted: return NSLocalizedString("6 任务完成", comment: "")
        case .userPromptSubmit: return NSLocalizedString("7 用户提交", comment: "")
        case .sessionEnd: return NSLocalizedString("8 会话结束", comment: "")
        }
    }

    var id: UInt8 { rawValue }

    static let workflowOrder: [IDEState] = [
        .sessionStart,
        .userPromptSubmit,
        .preToolUse,
        .permissionRequest,
        .postToolUse,
        .notification,
        .taskCompleted,
        .stop,
        .sessionEnd,
    ]

    var shortLabel: String {
        switch self {
        case .notification: return NSLocalizedString("通知", comment: "")
        case .permissionRequest: return NSLocalizedString("等待授权", comment: "")
        case .postToolUse: return NSLocalizedString("工具完毕", comment: "")
        case .preToolUse: return NSLocalizedString("工具执行", comment: "")
        case .sessionStart: return NSLocalizedString("会话开始", comment: "")
        case .stop: return NSLocalizedString("停止", comment: "")
        case .taskCompleted: return NSLocalizedString("任务完成", comment: "")
        case .userPromptSubmit: return NSLocalizedString("用户提交", comment: "")
        case .sessionEnd: return NSLocalizedString("会话结束", comment: "")
        }
    }
}

/// 设备状态响应解析结果
struct AhaKeyDeviceStatus {
    let battery: Int
    let signal: Int
    let firmwareMain: Int
    let firmwareSub: Int
    let workMode: Int
    let lightMode: Int
    let switchState: Int
    let brightness: Int
    let activePictureSet: Int
}

struct AhaKeyPictureState {
    let mode: Int
    let startIndex: Int
    let picLength: Int
    let frameInterval: Int
    let allModeMaxPic: Int
}

struct AhaKeyTaskPictureState: Hashable {
    let mode: Int
    let set: Int
    let state: Int
    let startIndex: Int
    let picLength: Int
    let frameInterval: Int
    let allModeMaxPic: Int
    let activeSet: Int
}

/// AhaKey 协议响应解析器
enum AhaKeyResponseParser {
    static func parseCommandResponse(_ data: Data) -> (cmd: UInt8, status: UInt8, payload: Data)? {
        guard isProtocolFrame(data), data.count >= 6 else { return nil }
        let cmd = data[2]
        let status = data[3]
        let payload = data.count > 6 ? Data(data[4 ..< data.count - 2]) : Data()
        return (cmd, status, payload)
    }

    /// 尝试从 notify 数据中解析设备状态
    /// 实际格式: AA BB [cmd_echo] [battery] [signal] [fw_main] [fw_sub] [work] [light] [switch] ... CC DD
    /// 第一个 payload 字节是命令回显（0x00），真实数据从第二字节开始
    static func parseDeviceStatus(_ data: Data) -> AhaKeyDeviceStatus? {
        // header(2) + cmd_echo(1) + 7 bytes status + trailer(2) = 12 bytes minimum
        guard data.count >= 12,
              data[0] == 0xAA, data[1] == 0xBB,
              data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD else {
            return nil
        }

        let payload = data[2 ..< data.count - 2]
        // payload[0] = command echo (0x00), skip it
        guard payload.count >= 8, payload[payload.startIndex] == 0x00 else { return nil }

        let base = payload.startIndex + 1 // skip cmd echo
        let brightness = payload.count >= 9 ? Int(payload[base + 7]) : 35
        let activePictureSet = payload.count >= 10 ? Int(payload[base + 8]) : 0
        return AhaKeyDeviceStatus(
            battery: Int(payload[base]),
            signal: Int(Int8(bitPattern: payload[base + 1])),
            firmwareMain: Int(payload[base + 2]),
            firmwareSub: Int(payload[base + 3]),
            workMode: Int(payload[base + 4]),
            lightMode: Int(payload[base + 5]),
            switchState: Int(payload[base + 6]),
            brightness: brightness,
            activePictureSet: activePictureSet
        )
    }

    static func parsePictureStateResponse(_ payload: Data) -> AhaKeyPictureState? {
        guard payload.count >= 9 else { return nil }

        let mode = Int(payload[0])
        let startIndex = Int(UInt16(payload[1]) | (UInt16(payload[2]) << 8))
        let picLength = Int(UInt16(payload[3]) | (UInt16(payload[4]) << 8))
        let frameInterval = Int(UInt16(payload[5]) | (UInt16(payload[6]) << 8))
        let allModeMaxPic = Int(UInt16(payload[7]) | (UInt16(payload[8]) << 8))

        return AhaKeyPictureState(
            mode: mode,
            startIndex: startIndex,
            picLength: picLength,
            frameInterval: frameInterval,
            allModeMaxPic: allModeMaxPic
        )
    }

    static func parseTaskPictureStateResponse(_ payload: Data) -> AhaKeyTaskPictureState? {
        guard payload.count >= 10 else { return nil }
        return AhaKeyTaskPictureState(
            mode: Int(payload[0]), set: 0, state: Int(payload[1]),
            startIndex: Int(UInt16(payload[2]) | (UInt16(payload[3]) << 8)),
            picLength: Int(UInt16(payload[4]) | (UInt16(payload[5]) << 8)),
            frameInterval: Int(UInt16(payload[6]) | (UInt16(payload[7]) << 8)),
            allModeMaxPic: Int(UInt16(payload[8]) | (UInt16(payload[9]) << 8)), activeSet: 0
        )
    }

    static func parseTaskPictureSetResponse(_ payload: Data) -> AhaKeyTaskPictureState? {
        guard payload.count >= 12 else { return nil }
        return AhaKeyTaskPictureState(
            mode: Int(payload[0]), set: Int(payload[1]), state: Int(payload[2]),
            startIndex: Int(UInt16(payload[3]) | (UInt16(payload[4]) << 8)),
            picLength: Int(UInt16(payload[5]) | (UInt16(payload[6]) << 8)),
            frameInterval: Int(UInt16(payload[7]) | (UInt16(payload[8]) << 8)),
            allModeMaxPic: Int(UInt16(payload[9]) | (UInt16(payload[10]) << 8)), activeSet: Int(payload[11])
        )
    }

    /// 检查是否是 AhaKey 协议帧
    static func isProtocolFrame(_ data: Data) -> Bool {
        data.count >= 4
            && data[0] == 0xAA && data[1] == 0xBB
            && data[data.count - 2] == 0xCC && data[data.count - 1] == 0xDD
    }
}

/// 常用 HID Usage ID
enum HIDUsage {
    // 修饰键
    static let leftControl: UInt8 = 0xE0
    static let leftShift: UInt8 = 0xE1
    static let leftAlt: UInt8 = 0xE2
    static let leftGUI: UInt8 = 0xE3
    static let rightControl: UInt8 = 0xE4
    static let rightShift: UInt8 = 0xE5
    static let rightAlt: UInt8 = 0xE6
    static let rightGUI: UInt8 = 0xE7

    // 功能键
    static let f1: UInt8 = 0x3A
    static let f2: UInt8 = 0x3B
    static let f3: UInt8 = 0x3C
    static let f4: UInt8 = 0x3D
    static let f5: UInt8 = 0x3E
    static let f6: UInt8 = 0x3F
    static let f7: UInt8 = 0x40
    static let f8: UInt8 = 0x41
    static let f9: UInt8 = 0x42
    static let f10: UInt8 = 0x43
    static let f11: UInt8 = 0x44
    static let f12: UInt8 = 0x45
    static let f13: UInt8 = 0x68
    static let f14: UInt8 = 0x69
    static let f15: UInt8 = 0x6A
    static let f16: UInt8 = 0x6B
    static let f17: UInt8 = 0x6C
    static let f18: UInt8 = 0x6D
    static let f19: UInt8 = 0x6E
    static let f20: UInt8 = 0x6F

    // 基础键
    static let enter: UInt8 = 0x28
    static let escape: UInt8 = 0x29
    static let backspace: UInt8 = 0x2A
    static let tab: UInt8 = 0x2B
    static let space: UInt8 = 0x2C
    static let capsLock: UInt8 = 0x39
    static let deleteForward: UInt8 = 0x4C
    static let insert: UInt8 = 0x49
    static let home: UInt8 = 0x4A
    static let pageUp: UInt8 = 0x4B
    static let end: UInt8 = 0x4D
    static let pageDown: UInt8 = 0x4E
    static let minus: UInt8 = 0x2D
    static let equal: UInt8 = 0x2E
    static let leftBracket: UInt8 = 0x2F
    static let rightBracket: UInt8 = 0x30
    static let backslash: UInt8 = 0x31
    static let semicolon: UInt8 = 0x33
    static let quote: UInt8 = 0x34
    static let grave: UInt8 = 0x35
    static let comma: UInt8 = 0x36
    static let period: UInt8 = 0x37
    static let slash: UInt8 = 0x38
    static let keypadSlash: UInt8 = 0x54
    static let keypadAsterisk: UInt8 = 0x55
    static let keypadMinus: UInt8 = 0x56
    static let keypadPlus: UInt8 = 0x57
    static let keypadEnter: UInt8 = 0x58
    static let keypad1: UInt8 = 0x59
    static let keypad2: UInt8 = 0x5A
    static let keypad3: UInt8 = 0x5B
    static let keypad4: UInt8 = 0x5C
    static let keypad5: UInt8 = 0x5D
    static let keypad6: UInt8 = 0x5E
    static let keypad7: UInt8 = 0x5F
    static let keypad8: UInt8 = 0x60
    static let keypad9: UInt8 = 0x61
    static let keypad0: UInt8 = 0x62
    static let keypadPeriod: UInt8 = 0x63

    // 方向键
    static let rightArrow: UInt8 = 0x4F
    static let leftArrow: UInt8 = 0x50
    static let downArrow: UInt8 = 0x51
    static let upArrow: UInt8 = 0x52

    /// 所有可用的键码选项（用于 UI 选择器）
    static let allOptions: [(name: String, code: UInt8)] = [
        // 功能键
        ("F1", f1), ("F2", f2), ("F3", f3), ("F4", f4),
        ("F5", f5), ("F6", f6), ("F7", f7), ("F8", f8),
        ("F9", f9), ("F10", f10), ("F11", f11), ("F12", f12),
        ("F13", f13), ("F14", f14), ("F15", f15), ("F16", f16),
        ("F17", f17), ("F18", f18), ("F19", f19), ("F20", f20),
        // 基础键
        ("Enter", enter), ("Escape", escape), ("Backspace", backspace),
        ("Tab", tab), ("Space", space), ("CapsLock", capsLock),
        ("Delete", deleteForward), ("Insert", insert), ("Home", home),
        ("End", end), ("Page Up", pageUp), ("Page Down", pageDown),
        ("-", minus), ("=", equal), ("[", leftBracket), ("]", rightBracket),
        ("\\", backslash), (";", semicolon), ("'", quote), ("`", grave),
        (",", comma), (".", period), ("/", slash),
        // 方向键
        ("→", rightArrow), ("←", leftArrow), ("↓", downArrow), ("↑", upArrow),
        // 字母键
        ("A", 0x04), ("B", 0x05), ("C", 0x06), ("D", 0x07),
        ("E", 0x08), ("F", 0x09), ("G", 0x0A), ("H", 0x0B),
        ("I", 0x0C), ("J", 0x0D), ("K", 0x0E), ("L", 0x0F),
        ("M", 0x10), ("N", 0x11), ("O", 0x12), ("P", 0x13),
        ("Q", 0x14), ("R", 0x15), ("S", 0x16), ("T", 0x17),
        ("U", 0x18), ("V", 0x19), ("W", 0x1A), ("X", 0x1B),
        ("Y", 0x1C), ("Z", 0x1D),
        // 数字键
        ("1", 0x1E), ("2", 0x1F), ("3", 0x20), ("4", 0x21),
        ("5", 0x22), ("6", 0x23), ("7", 0x24), ("8", 0x25),
        ("9", 0x26), ("0", 0x27),
        // 修饰键
        ("Left Ctrl", leftControl), ("Left Shift", leftShift),
        ("Left Alt", leftAlt), ("Left Cmd", leftGUI),
        ("Right Ctrl", rightControl), ("Right Shift", rightShift),
        ("Right Alt", rightAlt), ("Right Cmd", rightGUI),
        // 小键盘
        ("Keypad /", keypadSlash), ("Keypad *", keypadAsterisk),
        ("Keypad -", keypadMinus), ("Keypad +", keypadPlus),
        ("Keypad Enter", keypadEnter), ("Keypad 0", keypad0),
        ("Keypad 1", keypad1), ("Keypad 2", keypad2), ("Keypad 3", keypad3),
        ("Keypad 4", keypad4), ("Keypad 5", keypad5), ("Keypad 6", keypad6),
        ("Keypad 7", keypad7), ("Keypad 8", keypad8), ("Keypad 9", keypad9),
        ("Keypad .", keypadPeriod),
    ]

    static let primaryOptions = allOptions

    /// 根据键码查找名称
    static func name(for code: UInt8) -> String {
        allOptions.first { $0.code == code }?.name ?? String(format: "0x%02X", code)
    }

    static func hidCode(forMacKeyCode keyCode: UInt16) -> UInt8? {
        switch keyCode {
        case 0: return 0x04 // A
        case 1: return 0x16 // S
        case 2: return 0x07 // D
        case 3: return 0x09 // F
        case 4: return 0x0B // H
        case 5: return 0x0A // G
        case 6: return 0x1D // Z
        case 7: return 0x1B // X
        case 8: return 0x06 // C
        case 9: return 0x19 // V
        case 11: return 0x05 // B
        case 12: return 0x14 // Q
        case 13: return 0x1A // W
        case 14: return 0x08 // E
        case 15: return 0x15 // R
        case 16: return 0x1C // Y
        case 17: return 0x17 // T
        case 18: return 0x1E // 1
        case 19: return 0x1F // 2
        case 20: return 0x20 // 3
        case 21: return 0x21 // 4
        case 22: return 0x23 // 6
        case 23: return 0x22 // 5
        case 24: return equal
        case 25: return 0x26 // 9
        case 26: return 0x24 // 7
        case 27: return minus
        case 28: return 0x25 // 8
        case 29: return 0x27 // 0
        case 30: return rightBracket
        case 31: return 0x12 // O
        case 32: return 0x18 // U
        case 33: return leftBracket
        case 34: return 0x0C // I
        case 35: return 0x13 // P
        case 36: return enter
        case 37: return 0x0F // L
        case 38: return 0x0D // J
        case 39: return quote
        case 40: return 0x0E // K
        case 41: return semicolon
        case 42: return backslash
        case 43: return comma
        case 44: return slash
        case 45: return 0x11 // N
        case 46: return 0x10 // M
        case 47: return period
        case 48: return tab
        case 49: return space
        case 50: return grave
        case 51: return backspace
        case 53: return escape
        case 54: return rightGUI
        case 55: return leftGUI
        case 56: return leftShift
        case 57: return capsLock
        case 58: return leftAlt
        case 59: return leftControl
        case 60: return rightShift
        case 61: return rightAlt
        case 62: return rightControl
        case 63: return f19 // Fn/Globe reports as a function modifier on many Mac keyboards.
        case 64: return f17
        case 65: return keypadPeriod
        case 67: return keypadAsterisk
        case 69: return keypadPlus
        case 71: return 0x53 // Keypad Clear / Num Lock
        case 75: return keypadSlash
        case 76: return keypadEnter
        case 78: return keypadMinus
        case 79: return f18
        case 80: return f19
        case 82: return keypad0
        case 83: return keypad1
        case 84: return keypad2
        case 85: return keypad3
        case 86: return keypad4
        case 87: return keypad5
        case 88: return keypad6
        case 89: return keypad7
        case 90: return f20
        case 91: return keypad8
        case 92: return keypad9
        case 96: return f5
        case 97: return f6
        case 98: return f7
        case 99: return f3
        case 100: return f8
        case 101: return f9
        case 103: return f11
        case 105: return f13
        case 106: return f16
        case 107: return f14
        case 109: return f10
        case 111: return f12
        case 113: return f15
        case 115: return home
        case 116: return pageUp
        case 117: return deleteForward
        case 118: return f4
        case 119: return end
        case 120: return f2
        case 121: return pageDown
        case 122: return f1
        case 123: return leftArrow
        case 124: return rightArrow
        case 125: return downArrow
        case 126: return upArrow
        default: return nil
        }
    }
}

extension String {
    /// 设备 LCD 描述只稳定支持 ASCII；非 ASCII 字符会在设备端变成乱码。
    func sanitizedASCII(maxLength: Int) -> String {
        var result = String()
        result.reserveCapacity(min(maxLength, count))

        for scalar in unicodeScalars where scalar.isASCII {
            guard result.utf8.count < maxLength else { break }
            result.unicodeScalars.append(scalar)
        }

        return result
    }

    var containsNonASCII: Bool {
        unicodeScalars.contains(where: { !$0.isASCII })
    }
}
