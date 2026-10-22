import CryptoKit
import Foundation
import AhaKeyConfigShared

// Keep existing App call sites and test imports while release tooling shares
// the identical HEX parser and CH582 address limits.
typealias FirmwareImageDescriptor = AhaKeyConfigShared.FirmwareImageDescriptor
typealias FirmwareImageValidationError = AhaKeyConfigShared.FirmwareImageValidationError
typealias FirmwareImageValidator = AhaKeyConfigShared.FirmwareImageValidator

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
    case awaitingRuntimeVerification
    case verifyingRuntime
    case success
    case cancelled
    case failed(String)

    var title: String {
        switch self {
        case .idle: return NSLocalizedString("准备烧录器", comment: "")
        case .validating: return NSLocalizedString("正在校验固件", comment: "")
        case .ready: return NSLocalizedString("固件已校验，可以开始", comment: "")
        case .waitingForDevice: return NSLocalizedString("等待 CH582 USB ISP", comment: "")
        case .erasingDataFlash: return NSLocalizedString("正在清空 DataFlash", comment: "")
        case .erasingCodeFlash: return NSLocalizedString("正在清空 CodeFlash", comment: "")
        case .flashing: return NSLocalizedString("正在写入、校验并复位", comment: "")
        case .awaitingRuntimeVerification: return NSLocalizedString("写入校验通过，待重连确认", comment: "")
        case .verifyingRuntime: return NSLocalizedString("正在核对新固件连接", comment: "")
        case .success: return NSLocalizedString("升级验证通过", comment: "")
        case .cancelled: return NSLocalizedString("已取消，未执行擦除", comment: "")
        case .failed: return NSLocalizedString("烧录失败", comment: "")
        }
    }

    var isBusy: Bool {
        switch self {
        case .validating, .waitingForDevice, .erasingDataFlash, .erasingCodeFlash, .flashing, .verifyingRuntime:
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
        case .awaitingRuntimeVerification: return 0.9
        case .verifyingRuntime: return nil
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
    @Published private(set) var selectedCatalogCandidate: FirmwareInstallCandidate?
    var expectedCatalogKey: String? { selectedCatalogCandidate?.entry.key }
    @Published private(set) var runtimeVerificationMessage: String?

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

    func selectCustomFirmware(at url: URL, match: ((FirmwareImageDescriptor) -> FirmwareInstallCandidate?)? = nil) {
        validateFirmware(at: url, isBundled: false, match: match)
    }

    func selectCatalogFirmware(at url: URL, candidate: FirmwareInstallCandidate) {
        guard candidate.canInstall else { return }
        validateFirmware(at: url, isBundled: false, candidate: candidate)
    }

    func verifyRuntime(ble: AhaKeyBLEManager, session: StudioInspectorSession) async {
        guard phase == .awaitingRuntimeVerification else { return }
        transition(to: .verifyingRuntime)
        do {
            let actualKey = try await session.withConnection { context in
                let profile = try await ble.readFirmwareCapabilityProfile(forceStatusReadback: true)
                try session.validate(context)
                switch profile.identity {
                case .knownWS2Catalog: return FirmwareCapabilityProfile.ws2CatalogKey as String?
                case .verifiedCatalog(let key, _): return key
                case .unknown(let key): return key
                case .legacy: return nil
                }
            }
            let result = FirmwarePostFlashVerification.evaluate(expectedKey: expectedCatalogKey, actualKey: actualKey,
                hasValidStatus: true, sameConnection: true)
            switch result {
            case .verified:
                runtimeVerificationMessage = NSLocalizedString("新固件已重新连接，设备状态及版本标识与目标一致。", comment: "")
                transition(to: .success)
            case .missingExpectedIdentity:
                runtimeVerificationMessage = NSLocalizedString("已读到设备，但此 HEX 没有可信目录中的预期版本标识，无法确认完整升级结果。", comment: "")
                transition(to: .awaitingRuntimeVerification)
            default:
                runtimeVerificationMessage = NSLocalizedString("设备版本与预期不一致，尚未确认升级成功。请核对所选固件和连接的键盘。", comment: "")
                transition(to: .awaitingRuntimeVerification)
            }
        } catch {
            runtimeVerificationMessage = String(format: NSLocalizedString("暂未完成新固件连接核验：%@", comment: ""), KeyboardSettingsFeedback.message(for: error))
            transition(to: .awaitingRuntimeVerification)
        }
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

    private func validateFirmware(at url: URL, isBundled: Bool, candidate: FirmwareInstallCandidate? = nil,
        match: ((FirmwareImageDescriptor) -> FirmwareInstallCandidate?)? = nil) {
        guard !phase.isBusy else { return }
        validationTask?.cancel()
        transition(to: .validating)
        selectedFirmware = nil
        selectedCatalogCandidate = nil
        runtimeVerificationMessage = nil
        chipInfo = ""
        hasStartedDestructiveOperation = false

        validationTask = Task { [weak self] in
            do {
                let descriptor = try await Task.detached(priority: .userInitiated) {
                    try FirmwareImageValidator.validate(url: url, isBundled: isBundled)
                }.value
                try Task.checkCancellation()

                let candidate = candidate ?? match?(descriptor)
                if let candidate {
                    guard candidate.canInstall, let artifact = candidate.entry.artifact,
                          descriptor.sha256 == artifact.sha256, descriptor.byteCount == artifact.byteCount else {
                        throw FirmwareArtifactVerification.Failure.wrongDigest
                    }
                }

                if isBundled, descriptor.sha256 != AhaKeyFirmwareFlasherResources.bundledFirmwareSHA256 {
                    throw FirmwareFlasherError.bundledFirmwareIntegrity(
                        expected: AhaKeyFirmwareFlasherResources.bundledFirmwareSHA256,
                        actual: descriptor.sha256
                    )
                }

                guard let self else { return }
                _ = try self.resolveToolURL()
                self.selectedFirmware = descriptor
                self.selectedCatalogCandidate = candidate
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

            transition(to: .awaitingRuntimeVerification)
            runtimeVerificationMessage = NSLocalizedString("请拔掉 USB、移除 BOOT—GND 短接，再正常无线开机；重新连接核验后才能确认完整结果。", comment: "")
            appendLog("写入和代码校验通过；新固件连接尚未确认。")
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
