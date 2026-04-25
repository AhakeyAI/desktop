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
    static let oledMaxFrames = 74
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
    ///   - mode: 工作模式 0-2
    ///   - keyIndex: 0=Key1, 1=Key2, 2=Key3, 3=Key4
    ///   - hidCodes: HID Usage ID 数组（修饰键在前，普通键在后，最多 98 字节）
    static func setKeyMapping(mode: UInt8 = 0, keyIndex: UInt8, hidCodes: [UInt8]) -> Data {
        let payload: [UInt8] = [subShortcut, mode, keyIndex] + hidCodes
        return Data(header + [cmdUpdateCustomKey] + payload + trailer)
    }

    /// 描述写入 → AA BB 73 75 [mode] [key_index] [utf8...] CC DD
    /// - Parameters:
    ///   - mode: 工作模式 0-2
    ///   - keyIndex: 0=Key1, 1=Key2, 2=Key3, 3=Key4
    ///   - text: 显示在 OLED 上的按键描述（最多 20 字节 ASCII）
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

    /// 更新 OLED 动画参数 → AA BB 82 [mode] [start_index:2 LE] [frame_count:2 LE] [time_delay:2 LE] CC DD
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

    /// IDE 状态同步 → AA BB 90 [state] CC DD
    /// 驱动键盘 LED 变色，反映 Claude/Cursor 当前状态
    static func updateState(_ state: IDEState) -> Data {
        Data(header + [cmdUpdateState, state.rawValue] + trailer)
    }
}

/// IDE 状态枚举（原厂 ClaudeState）
/// 发送到键盘后驱动 LED 颜色变化
enum IDEState: UInt8, CaseIterable {
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
        case .notification: return "0 通知"
        case .permissionRequest: return "1 等待授权"
        case .postToolUse: return "2 工具完毕"
        case .preToolUse: return "3 工具执行"
        case .sessionStart: return "4 会话开始"
        case .stop: return "5 停止"
        case .taskCompleted: return "6 任务完成"
        case .userPromptSubmit: return "7 用户提交"
        case .sessionEnd: return "8 会话结束"
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
}

struct AhaKeyPictureState {
    let mode: Int
    let startIndex: Int
    let picLength: Int
    let frameInterval: Int
    let allModeMaxPic: Int
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
        return AhaKeyDeviceStatus(
            battery: Int(payload[base]),
            signal: Int(Int8(bitPattern: payload[base + 1])),
            firmwareMain: Int(payload[base + 2]),
            firmwareSub: Int(payload[base + 3]),
            workMode: Int(payload[base + 4]),
            lightMode: Int(payload[base + 5]),
            switchState: Int(payload[base + 6])
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
        ("Delete", deleteForward),
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
    ]

    static let primaryOptions = allOptions

    /// 根据键码查找名称
    static func name(for code: UInt8) -> String {
        allOptions.first { $0.code == code }?.name ?? String(format: "0x%02X", code)
    }
}

extension String {
    /// 设备 OLED 描述只稳定支持 ASCII；非 ASCII 字符会在设备端变成乱码。
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
