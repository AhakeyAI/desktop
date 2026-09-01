import CryptoKit
import Foundation

struct FirmwareImageDescriptor: Equatable, Sendable {
    let url: URL
    let fileName: String
    let byteCount: Int
    let sha256: String
    let isBundled: Bool

    var formattedByteCount: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteCount))
    }
}

enum FirmwareImageValidationError: LocalizedError, Equatable {
    case invalidExtension
    case unreadable
    case empty
    case tooLarge(maxBytes: Int)
    case invalidText
    case malformedRecord(line: Int)
    case invalidChecksum(line: Int)
    case unsupportedRecordType(line: Int, type: UInt8)
    case addressOutOfRange(line: Int, maximumExclusive: UInt64)
    case missingDataRecord
    case missingEOF

    var errorDescription: String? {
        switch self {
        case .invalidExtension:
            return "请选择扩展名为 .hex 的 Intel HEX 固件。"
        case .unreadable:
            return "无法读取所选固件文件。"
        case .empty:
            return "所选固件文件为空。"
        case .tooLarge(let maxBytes):
            return "固件文件超过 \(maxBytes / 1024 / 1024) MB 安全上限。"
        case .invalidText:
            return "固件不是有效的 UTF-8 / ASCII Intel HEX 文本。"
        case .malformedRecord(let line):
            return "Intel HEX 第 \(line) 行格式不完整。"
        case .invalidChecksum(let line):
            return "Intel HEX 第 \(line) 行校验和错误。"
        case .unsupportedRecordType(let line, let type):
            return "Intel HEX 第 \(line) 行使用了不支持的记录类型 0x\(String(format: "%02X", type))。"
        case .addressOutOfRange(let line, let maximumExclusive):
            return "Intel HEX 第 \(line) 行超出 CH582 CodeFlash 地址范围（0x000000–0x\(String(format: "%06llX", maximumExclusive - 1))）。"
        case .missingDataRecord:
            return "Intel HEX 中没有可写入的数据记录。"
        case .missingEOF:
            return "Intel HEX 缺少 EOF 结束记录。"
        }
    }
}

enum FirmwareImageValidator {
    static let maximumFileSize = 16 * 1024 * 1024
    static let ch582CodeFlashSize: UInt64 = 448 * 1024

    static func validate(url: URL, isBundled: Bool = false) throws -> FirmwareImageDescriptor {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw FirmwareImageValidationError.unreadable
        }
        return try validate(data: data, sourceURL: url, isBundled: isBundled)
    }

    static func validate(
        data: Data,
        sourceURL url: URL,
        isBundled: Bool = false
    ) throws -> FirmwareImageDescriptor {
        guard url.pathExtension.lowercased() == "hex" else {
            throw FirmwareImageValidationError.invalidExtension
        }
        guard !data.isEmpty else { throw FirmwareImageValidationError.empty }
        guard data.count <= maximumFileSize else {
            throw FirmwareImageValidationError.tooLarge(maxBytes: maximumFileSize)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw FirmwareImageValidationError.invalidText
        }

        var hasDataRecord = false
        var hasEOF = false
        var baseAddress: UInt64 = 0
        let lines = text.components(separatedBy: .newlines)

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard line.first == ":" else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }

            let payload = String(line.dropFirst())
            guard payload.count.isMultiple(of: 2), payload.count >= 10 else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }

            var bytes: [UInt8] = []
            bytes.reserveCapacity(payload.count / 2)
            var index = payload.startIndex
            while index < payload.endIndex {
                let next = payload.index(index, offsetBy: 2)
                guard let byte = UInt8(payload[index..<next], radix: 16) else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                bytes.append(byte)
                index = next
            }

            let dataLength = Int(bytes[0])
            guard bytes.count == dataLength + 5 else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }
            guard bytes.reduce(0, { ($0 + Int($1)) & 0xFF }) == 0 else {
                throw FirmwareImageValidationError.invalidChecksum(line: lineNumber)
            }
            guard !hasEOF else {
                throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
            }

            switch bytes[3] {
            case 0x00:
                let recordAddress = UInt64(bytes[1]) << 8 | UInt64(bytes[2])
                let startAddress = baseAddress + recordAddress
                let endAddress = startAddress + UInt64(dataLength)
                guard endAddress <= ch582CodeFlashSize else {
                    throw FirmwareImageValidationError.addressOutOfRange(
                        line: lineNumber,
                        maximumExclusive: ch582CodeFlashSize
                    )
                }
                hasDataRecord = hasDataRecord || dataLength > 0
            case 0x01:
                guard dataLength == 0, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                hasEOF = true
            case 0x02:
                guard dataLength == 2, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                baseAddress = (UInt64(bytes[4]) << 8 | UInt64(bytes[5])) << 4
            case 0x03:
                guard dataLength == 4, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
            case 0x04:
                guard dataLength == 2, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
                baseAddress = (UInt64(bytes[4]) << 8 | UInt64(bytes[5])) << 16
            case 0x05:
                guard dataLength == 4, bytes[1] == 0, bytes[2] == 0 else {
                    throw FirmwareImageValidationError.malformedRecord(line: lineNumber)
                }
            default:
                throw FirmwareImageValidationError.unsupportedRecordType(
                    line: lineNumber,
                    type: bytes[3]
                )
            }
        }

        guard hasDataRecord else { throw FirmwareImageValidationError.missingDataRecord }
        guard hasEOF else { throw FirmwareImageValidationError.missingEOF }

        return FirmwareImageDescriptor(
            url: url,
            fileName: url.lastPathComponent,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            isBundled: isBundled
        )
    }
}

enum FirmwareImageStager {
    static func stage(_ firmware: FirmwareImageDescriptor) throws -> URL {
        guard let data = try? Data(contentsOf: firmware.url, options: [.mappedIfSafe]) else {
            throw FirmwareImageValidationError.unreadable
        }
        let revalidated = try FirmwareImageValidator.validate(
            data: data,
            sourceURL: firmware.url,
            isBundled: firmware.isBundled
        )
        guard revalidated.sha256 == firmware.sha256 else {
            throw FirmwareFlasherError.firmwareChanged
        }

        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AhaKeyStudio-Firmware-\(UUID().uuidString)")
            .appendingPathExtension("hex")
        do {
            try data.write(to: stagedURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o400],
                ofItemAtPath: stagedURL.path
            )
            return stagedURL
        } catch {
            try? FileManager.default.removeItem(at: stagedURL)
            throw FirmwareFlasherError.stagingFailed(error.localizedDescription)
        }
    }
}

enum AhaKeyFirmwareFlasherResources {
    static let bundledFirmwareFileName = "AhaKey-X1-firmware-eternal-dev-5a84c2a-1.4.6.hex"
    static let bundledFirmwareSHA256 = "f7df11438263aadedb5ad2c05e6f7162c66afc3d36193fac87d7399a7f25976e"
}

enum FirmwareFlashPhase: Equatable {
    case idle
    case validating
    case ready
    case waitingForDevice
    case erasingDataFlash
    case erasingCodeFlash
    case flashing
    case success
    case cancelled
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "准备烧录器"
        case .validating: return "正在校验固件"
        case .ready: return "固件已校验，可以开始"
        case .waitingForDevice: return "等待 CH582 USB ISP"
        case .erasingDataFlash: return "正在清空 DataFlash"
        case .erasingCodeFlash: return "正在清空 CodeFlash"
        case .flashing: return "正在写入、校验并复位"
        case .success: return "烧录成功"
        case .cancelled: return "已取消，未执行擦除"
        case .failed: return "烧录失败"
        }
    }

    var isBusy: Bool {
        switch self {
        case .validating, .waitingForDevice, .erasingDataFlash, .erasingCodeFlash, .flashing:
            return true
        default:
            return false
        }
    }

    var canCancelSafely: Bool {
        self == .validating || self == .waitingForDevice
    }

    var isDestructive: Bool {
        self == .erasingDataFlash || self == .erasingCodeFlash || self == .flashing
    }

    var progress: Double? {
        switch self {
        case .idle: return 0
        case .validating: return nil
        case .ready: return 0
        case .waitingForDevice: return nil
        case .erasingDataFlash: return 0.2
        case .erasingCodeFlash: return 0.45
        case .flashing: return 0.7
        case .success: return 1
        case .cancelled, .failed: return 0
        }
    }
}

final class FirmwareFlashActivity {
    static let shared = FirmwareFlashActivity()
    var preventsApplicationTermination = false
    private init() {}
}

private struct WCHISPCommandResult: Sendable {
    let status: Int32
    let output: String
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

private actor WCHISPProcessRunner {
    private var activeProcess: Process?

    func run(executable: URL, arguments: [String]) async throws -> WCHISPCommandResult {
        try Task.checkCancellation()

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let outputBuffer = ProcessOutputBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }
        activeProcess = process
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil
        }

        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                        process.waitUntilExit()
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                        continuation.resume(returning: WCHISPCommandResult(
                            status: process.terminationStatus,
                            output: outputBuffer.string()
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }

        try Task.checkCancellation()
        return result
    }

    func cancel() {
        guard let activeProcess, activeProcess.isRunning else { return }
        activeProcess.terminate()
    }
}

enum FirmwareFlasherError: LocalizedError, Equatable {
    case resourceMissing(String)
    case bundledFirmwareIntegrity(expected: String, actual: String)
    case deviceTimeout
    case wrongChip(String)
    case commandFailed(step: String, status: Int32, output: String)
    case interruptedAfterErase
    case firmwareChanged
    case stagingFailed(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "应用包缺少烧录资源：\(name)。请重新安装完整版本。"
        case .bundledFirmwareIntegrity(let expected, let actual):
            return "内置固件校验失败。期望 \(expected)，实际 \(actual)。"
        case .deviceTimeout:
            return "60 秒内未检测到 CH582 ISP。请检查数据线，以及 BOOT（PB22）与 GND 的短接和上电顺序。"
        case .wrongChip(let output):
            return "检测到的目标不是 CH582，已在擦除前停止。\n\(output)"
        case .commandFailed(let step, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(step)失败（退出码 \(status)）。\(detail.isEmpty ? "" : "\n\(detail)")"
        case .interruptedAfterErase:
            return "烧录在擦除开始后中断。设备可能没有可运行固件，请保持 USB ISP 连接并重新烧录。"
        case .firmwareChanged:
            return "所选固件在校验后发生了变化，已在访问设备前停止。请重新选择并确认 SHA-256。"
        case .stagingFailed(let detail):
            return "无法准备安全的固件临时副本：\(detail)"
        }
    }
}

@MainActor
final class AhaKeyFirmwareFlasher: ObservableObject {
    @Published private(set) var selectedFirmware: FirmwareImageDescriptor?
    @Published private(set) var phase: FirmwareFlashPhase = .idle
    @Published private(set) var chipInfo = ""
    @Published private(set) var logLines: [String] = []
    @Published private(set) var hasStartedDestructiveOperation = false

    private let bundle: Bundle
    private let processRunner = WCHISPProcessRunner()
    private var validationTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var systemActivity: NSObjectProtocol?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    deinit {
        validationTask?.cancel()
        flashTask?.cancel()
        let runner = processRunner
        Task { await runner.cancel() }
        if let systemActivity {
            ProcessInfo.processInfo.endActivity(systemActivity)
        }
        FirmwareFlashActivity.shared.preventsApplicationTermination = false
    }

    func loadBundledFirmwareIfNeeded() {
        guard selectedFirmware == nil, !phase.isBusy else { return }
        selectBundledFirmware()
    }

    func selectBundledFirmware() {
        guard let url = bundle.url(
            forResource: AhaKeyFirmwareFlasherResources.bundledFirmwareFileName,
            withExtension: nil,
            subdirectory: "FirmwareFlasher/firmware"
        ) else {
            fail(FirmwareFlasherError.resourceMissing(AhaKeyFirmwareFlasherResources.bundledFirmwareFileName))
            return
        }
        validateFirmware(at: url, isBundled: true)
    }

    func selectCustomFirmware(at url: URL) {
        validateFirmware(at: url, isBundled: false)
    }

    func startFlashing() {
        guard flashTask == nil, let firmware = selectedFirmware, phase == .ready else { return }
        chipInfo = ""
        hasStartedDestructiveOperation = false
        logLines.removeAll(keepingCapacity: true)
        appendLog("固件：\(firmware.fileName)")
        appendLog("SHA-256：\(firmware.sha256)")
        appendLog("目标芯片：CH582M")

        flashTask = Task { [weak self] in
            await self?.performFlash(firmware: firmware)
        }
    }

    func cancelSafely() {
        guard phase.canCancelSafely else { return }
        validationTask?.cancel()
        flashTask?.cancel()
        Task { await processRunner.cancel() }
        transition(to: .cancelled)
        appendLog("用户已取消；尚未执行擦除。")
    }

    private func validateFirmware(at url: URL, isBundled: Bool) {
        guard !phase.isBusy else { return }
        validationTask?.cancel()
        transition(to: .validating)
        selectedFirmware = nil
        chipInfo = ""
        hasStartedDestructiveOperation = false

        validationTask = Task { [weak self] in
            do {
                let descriptor = try await Task.detached(priority: .userInitiated) {
                    try FirmwareImageValidator.validate(url: url, isBundled: isBundled)
                }.value
                try Task.checkCancellation()

                if isBundled, descriptor.sha256 != AhaKeyFirmwareFlasherResources.bundledFirmwareSHA256 {
                    throw FirmwareFlasherError.bundledFirmwareIntegrity(
                        expected: AhaKeyFirmwareFlasherResources.bundledFirmwareSHA256,
                        actual: descriptor.sha256
                    )
                }

                guard let self else { return }
                _ = try self.resolveToolURL()
                self.selectedFirmware = descriptor
                self.transition(to: .ready)
                self.logLines = ["固件校验通过：\(descriptor.fileName)"]
            } catch is CancellationError {
                guard let self else { return }
                self.transition(to: .cancelled)
            } catch {
                self?.fail(error)
            }
            self?.validationTask = nil
        }
    }

    private func performFlash(firmware: FirmwareImageDescriptor) async {
        var stagedFirmwareURL: URL?
        systemActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "AhaKey X1 firmware flashing"
        )
        defer {
            if let systemActivity {
                ProcessInfo.processInfo.endActivity(systemActivity)
                self.systemActivity = nil
            }
            if let stagedFirmwareURL {
                try? FileManager.default.removeItem(at: stagedFirmwareURL)
            }
        }

        do {
            let flashImageURL = try await Task.detached(priority: .userInitiated) {
                try FirmwareImageStager.stage(firmware)
            }.value
            stagedFirmwareURL = flashImageURL
            appendLog("已创建并锁定校验后的固件临时副本。")

            let toolURL = try resolveToolURL()
            transition(to: .waitingForDevice)
            appendLog("等待 USB ISP：关闭键盘电源，短接 BOOT（PB22）与 GND 后插入 USB。")

            let info = try await waitForCH582(toolURL: toolURL)
            chipInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
            appendLog("已检测到 CH582。")
            appendProcessOutput(info)

            hasStartedDestructiveOperation = true
            transition(to: .erasingDataFlash)
            appendLog("开始清空 DataFlash；从现在起请勿拔线或退出 App。")
            try await runRequired(
                toolURL: toolURL,
                arguments: ["--usb", "eeprom", "erase"],
                step: "清空 DataFlash"
            )

            transition(to: .erasingCodeFlash)
            appendLog("开始清空全部 CodeFlash。")
            try await runRequired(
                toolURL: toolURL,
                arguments: ["--usb", "erase"],
                step: "清空 CodeFlash"
            )

            transition(to: .flashing)
            appendLog("开始写入、校验并复位运行。")
            try await runRequired(
                toolURL: toolURL,
                arguments: ["--usb", "flash", "--no-erase", flashImageURL.path],
                step: "写入与校验"
            )

            transition(to: .success)
            appendLog("烧录成功。请拔掉 USB、移除 BOOT—GND 短接，再正常开机。")
        } catch is CancellationError {
            if hasStartedDestructiveOperation {
                fail(FirmwareFlasherError.interruptedAfterErase)
            } else {
                transition(to: .cancelled)
                appendLog("用户已取消；尚未执行擦除。")
            }
        } catch {
            fail(error)
        }
        flashTask = nil
    }

    private func waitForCH582(toolURL: URL) async throws -> String {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            try Task.checkCancellation()
            let result = try await processRunner.run(
                executable: toolURL,
                arguments: ["--usb", "info", "--chip", "CH582"]
            )
            if result.status == 0 {
                guard result.output.localizedCaseInsensitiveContains("CH582") else {
                    throw FirmwareFlasherError.wrongChip(result.output)
                }
                return result.output
            }
            if result.output.contains("Chip:"), !result.output.localizedCaseInsensitiveContains("CH582") {
                throw FirmwareFlasherError.wrongChip(result.output)
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw FirmwareFlasherError.deviceTimeout
    }

    private func runRequired(toolURL: URL, arguments: [String], step: String) async throws {
        let result = try await processRunner.run(executable: toolURL, arguments: arguments)
        appendProcessOutput(result.output)
        guard result.status == 0 else {
            throw FirmwareFlasherError.commandFailed(
                step: step,
                status: result.status,
                output: result.output
            )
        }
    }

    private func resolveToolURL() throws -> URL {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        throw FirmwareFlasherError.resourceMissing("当前 Mac 架构对应的 wchisp")
        #endif

        guard let resourceURL = bundle.resourceURL else {
            throw FirmwareFlasherError.resourceMissing("Contents/Resources")
        }
        let toolURL = resourceURL
            .appendingPathComponent("FirmwareFlasher/tools", isDirectory: true)
            .appendingPathComponent(architecture, isDirectory: true)
            .appendingPathComponent("wchisp", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: toolURL.path) else {
            throw FirmwareFlasherError.resourceMissing("FirmwareFlasher/tools/\(architecture)/wchisp")
        }
        return toolURL
    }

    private func transition(to newPhase: FirmwareFlashPhase) {
        phase = newPhase
        FirmwareFlashActivity.shared.preventsApplicationTermination = newPhase.isDestructive
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        transition(to: .failed(message))
        appendLog("错误：\(message)")
        if hasStartedDestructiveOperation {
            appendLog("恢复建议：保持 USB ISP 连接，确认固件有效后重新执行全量烧录。")
        }
    }

    private func appendProcessOutput(_ output: String) {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .forEach(appendLog)
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 250 {
            logLines.removeFirst(logLines.count - 250)
        }
    }
}
