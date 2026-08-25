import Foundation

// MARK: - 线协议帧构造与程序执行 seam（WBS-5.6 切片 5）
//
// Runtime 侧独占的物理帧构造（移植自 App 侧 AhaKeyCommand，字节级兼容）。
// 执行层 `AhaKeyDeviceProgramExecutor` 把程序步骤翻译成「命令帧 + 数据块」序列，
// 通过回调 seam 落到真实 BLE；ACK/超时/取消由 seam 上报，executor 只做编排。

/// 物理帧构造器（AA BB [cmd] [payload] CC DD）。
public enum AhaKeyWireFrameBuilder {
    public static let header: [UInt8] = [0xAA, 0xBB]
    public static let trailer: [UInt8] = [0xCC, 0xDD]

    // 命令码（与固件 command_solve.c 对齐）
    public static let cmdSaveConfig: UInt8 = 0x04
    public static let cmdUpdateCustomKey: UInt8 = 0x73
    public static let cmdPrepareWrite: UInt8 = 0x80
    public static let cmdWriteResult: UInt8 = 0x81
    public static let cmdSetLightMapping: UInt8 = 0x84
    public static let cmdSetBrightness: UInt8 = 0x85
    public static let cmdUpdateTaskPicSet: UInt8 = 0x95
    public static let cmdSetActiveTaskPicSet: UInt8 = 0x97
    public static let cmdFinishTaskPicWrite: UInt8 = 0x98
    public static let cmdAbortPictureWrite: UInt8 = 0x9A
    public static let cmdPrepareSessionWrite: UInt8 = 0x9B

    public static let subShortcut: UInt8 = 0x73
    public static let subMacro: UInt8 = 0x74
    public static let subDescription: UInt8 = 0x75

    /// 程序步骤 → 命令帧。`.writeResourceChunk` 不走命令帧（数据特征直写），返回 nil。
    public static func commandFrame(for step: AhaKeyDeviceProgramStep) -> Data? {
        switch step {
        case .prepareWrite(let sessionID, let chunkLength, let address):
            var payload: [UInt8] = []
            let cmd: UInt8
            if let sessionID {
                cmd = cmdPrepareSessionWrite
                payload = [UInt8(sessionID & 0xFF), UInt8((sessionID >> 8) & 0xFF)]
            } else {
                cmd = cmdPrepareWrite
                payload = [0x00]
            }
            payload += [
                UInt8(chunkLength & 0xFF), UInt8((chunkLength >> 8) & 0xFF),
                UInt8(address & 0xFF), UInt8((address >> 8) & 0xFF),
                UInt8((address >> 16) & 0xFF), UInt8((address >> 24) & 0xFF),
            ]
            return frame(cmd, payload)
        case .abortSession(let sessionID):
            if let sessionID {
                return frame(cmdAbortPictureWrite,
                             [UInt8(sessionID & 0xFF), UInt8((sessionID >> 8) & 0xFF)])
            }
            return frame(cmdAbortPictureWrite, [])
        case .bindTaskPicture(let mode, let set, let state, let startIndex, let frameCount, let intervalMs):
            return frame(cmdUpdateTaskPicSet, [
                mode, set, state,
                UInt8(startIndex & 0xFF), UInt8((startIndex >> 8) & 0xFF),
                UInt8(frameCount & 0xFF), UInt8((frameCount >> 8) & 0xFF),
                UInt8(intervalMs & 0xFF), UInt8((intervalMs >> 8) & 0xFF),
            ])
        case .setActiveTaskPictureSet(let mode, let set):
            return frame(cmdSetActiveTaskPicSet, [mode, set])
        case .finishTaskPictureWrite:
            return frame(cmdFinishTaskPicWrite, [])
        case .setKeyShortcut(let mode, let keyIndex, let hidCodes):
            return frame(cmdUpdateCustomKey, [subShortcut, mode, keyIndex] + hidCodes)
        case .setKeyMacro(let mode, let keyIndex, let pairs):
            return frame(cmdUpdateCustomKey, [subMacro, mode, keyIndex] + pairs)
        case .setKeyDescription(let mode, let keyIndex, let text):
            let bytes = Array(text.asciiSanitized(maxLength: 20).utf8)
            return frame(cmdUpdateCustomKey, [subDescription, mode, keyIndex] + bytes)
        case .setLightMapping(let mode, let effects):
            return frame(cmdSetLightMapping, [mode] + effects)
        case .setBrightness(let value):
            return frame(cmdSetBrightness, [max(1, min(100, value))])
        case .saveConfig:
            return frame(cmdSaveConfig, [])
        case .writeResourceChunk:
            return nil
        }
    }

    /// 命令帧对应的期望 ACK 命令回显（executor 等待匹配）。
    public static func expectedAck(for step: AhaKeyDeviceProgramStep) -> UInt8? {
        commandFrame(for: step).map { $0[2] }
    }

    private static func frame(_ cmd: UInt8, _ payload: [UInt8]) -> Data {
        Data(header + [cmd] + payload + trailer)
    }
}

private extension String {
    /// 设备 LCD 描述只稳定支持 ASCII。
    func asciiSanitized(maxLength: Int) -> String {
        var result = String()
        for scalar in unicodeScalars where scalar.isASCII {
            guard result.utf8.count < maxLength else { break }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}

// MARK: - 程序执行器（编排 seam；真实 BLE 在 agent 侧实现）

/// 执行环境 seam：agent 用 CoreBluetooth 实现，测试用假实现。
public protocol AhaKeyDeviceProgramTransport: Sendable {
    /// 发送命令帧并等待匹配 ACK（超时/设备拒绝抛错）。
    func sendCommand(_ frame: Data, expectingAck ack: UInt8) async throws
    /// 直写资源数据块（data 特征，按包大小再切由实现负责）。
    func writeChunk(digest: AhaKeySHA256Digest, offset: Int, length: Int) async throws
    /// 取消检查点：用户已请求取消时返回 true。
    func isCancellationRequested() -> Bool
}

public enum AhaKeyDeviceProgramExecutionError: Error, Equatable {
    case cancelled
}

public enum AhaKeyDeviceProgramExecutor {
    /// 顺序执行程序；遇到 .writeResourceChunk 走数据通道，其余走命令 ACK。
    /// 会话式上传在失败时由调用层决定是否补 abortSession（程序已含收尾步骤）。
    public static func execute(
        _ program: [AhaKeyDeviceProgramStep],
        over transport: AhaKeyDeviceProgramTransport
    ) async throws {
        for step in program {
            if transport.isCancellationRequested() {
                throw AhaKeyDeviceProgramExecutionError.cancelled
            }
            if case .writeResourceChunk(let digest, let offset, let length) = step {
                try await transport.writeChunk(digest: digest, offset: offset, length: length)
            } else if let frame = AhaKeyWireFrameBuilder.commandFrame(for: step),
                      let ack = AhaKeyWireFrameBuilder.expectedAck(for: step) {
                try await transport.sendCommand(frame, expectingAck: ack)
            }
        }
    }
}
