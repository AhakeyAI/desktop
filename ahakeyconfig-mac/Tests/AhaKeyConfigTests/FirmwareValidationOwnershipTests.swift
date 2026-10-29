import Foundation
import Combine
import XCTest
@testable import AhaKeyConfig

final class FirmwareValidationOwnershipTests: XCTestCase {
    @MainActor
    func testFailedDetectionCanRetrySameImageWithoutReselecting() async throws {
        let image = try temporaryHEX(byte: 1)
        let (bundle, directory) = try temporaryToolBundle()
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: directory)
        }
        // Exercise a real terminal failure without waiting for a physical ISP.
        for architecture in ["arm64", "x86_64"] {
            let tool = directory.appendingPathComponent("Contents/Resources/FirmwareFlasher/tools/\(architecture)/wchisp")
            try Data("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$0.calls\"\nprintf 'Chip: CH579\\n'\n".utf8).write(to: tool)
        }
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle)
        flasher.selectCustomFirmware(at: image)
        await flasher.validationTask?.value
        let original = try XCTUnwrap(flasher.selectedFirmware)
        flasher.startFlashing()
        await flasher.flashTask?.value
        guard case .failed = flasher.phase else { return XCTFail("Detection must fail before retry") }
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
        XCTAssertEqual(flasher.selectedFirmware, original)

        flasher.startFlashing()
        let retry = flasher.flashTask
        XCTAssertNotNil(retry, "A failed attempt must accept an explicit retry without reselecting HEX")
        XCTAssertTrue(flasher.phase.isBusy, "Retry must synchronously lock the selected image")
        XCTAssertEqual(flasher.selectedFirmware, original)
        flasher.cancelSafely()
        await retry?.value
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
    }

    @MainActor
    func test180SecondDefaultAndTimeoutRetry() async throws {
        XCTAssertEqual(FirmwareISPWait.timeoutSeconds, 180)
        XCTAssertTrue(FirmwareFlasherError.deviceTimeout.errorDescription?.contains("180") == true)
        let image = try temporaryHEX(byte: 1)
        let (bundle, directory) = try temporaryToolBundle()
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: directory)
        }
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle, deviceWaitTimeout: 0.01)
        flasher.selectCustomFirmware(at: image)
        await flasher.validationTask?.value
        flasher.startFlashing()
        await flasher.flashTask?.value
        guard case .failed(let message) = flasher.phase else { return XCTFail("Missing ISP must time out") }
        XCTAssertEqual(message, FirmwareFlasherError.deviceTimeout.errorDescription)
        XCTAssertTrue(flasher.canStartFlashing)
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
        flasher.startFlashing()
        let retry = try XCTUnwrap(flasher.flashTask)
        flasher.cancelSafely()
        await retry.value
    }

    @MainActor
    func testCancelMustFinishCleanupBeforeRetry() async throws {
        let image = try temporaryHEX(byte: 1)
        let (bundle, directory) = try temporaryToolBundle()
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: directory)
        }
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle)
        flasher.selectCustomFirmware(at: image)
        await flasher.validationTask?.value
        flasher.startFlashing()
        let old = try XCTUnwrap(flasher.flashTask)
        flasher.cancelSafely()
        XCTAssertFalse(flasher.canStartFlashing)
        flasher.startFlashing()
        XCTAssertEqual(flasher.phase, .cancelled)
        await old.value
        XCTAssertTrue(flasher.canStartFlashing)
        flasher.startFlashing()
        let retry = try XCTUnwrap(flasher.flashTask)
        XCTAssertEqual(flasher.phase, .validating)
        flasher.cancelSafely()
        await retry.value
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
    }

    @MainActor
    func testChangedImageRetryStopsBeforeDeviceAccess() async throws {
        let image = try temporaryHEX(byte: 1)
        let changed = try temporaryHEX(byte: 2)
        let (bundle, directory) = try temporaryToolBundle(infoSucceeds: true)
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: changed)
            try? FileManager.default.removeItem(at: directory)
        }
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle)
        flasher.selectCustomFirmware(at: image)
        await flasher.validationTask?.value
        let observation = flasher.$chipInfo.dropFirst().sink { info in
            if info.contains("CH582") { flasher.cancelSafely() }
        }
        flasher.startFlashing()
        await flasher.flashTask?.value
        observation.cancel()
        let before = try recordedToolCalls(in: directory)
        try Data(contentsOf: changed).write(to: image)
        flasher.startFlashing()
        await flasher.flashTask?.value
        guard case .failed(let message) = flasher.phase else { return XCTFail("Changed HEX must be rejected") }
        XCTAssertEqual(message, FirmwareFlasherError.firmwareChanged.errorDescription)
        XCTAssertEqual(try recordedToolCalls(in: directory), before)
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
    }

    @MainActor
    func testFailureAfterEraseAllowsNewAttempt() async throws {
        let image = try temporaryHEX(byte: 1)
        let (bundle, directory) = try temporaryToolBundle(infoSucceeds: true)
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: directory)
        }
        // The isolated fake tool accepts info, then fails the first erase.
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle)
        flasher.selectCustomFirmware(at: image)
        await flasher.validationTask?.value
        flasher.startFlashing()
        await flasher.flashTask?.value
        guard case .failed = flasher.phase else { return XCTFail("Erase fixture must fail") }
        XCTAssertTrue(flasher.hasStartedDestructiveOperation)
        XCTAssertTrue(flasher.canStartFlashing)
        XCTAssertEqual(try recordedToolCalls(in: directory), "--usb info --chip CH582\n--usb eeprom erase\n")
        flasher.startFlashing()
        let retry = try XCTUnwrap(flasher.flashTask)
        XCTAssertEqual(flasher.phase, .validating)
        flasher.cancelSafely()
        await retry.value
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
    }

    func testRetryEligibilityExcludesSuccessAndRuntimeVerification() {
        for phase: FirmwareFlashPhase in [.ready, .failed("test"), .cancelled] {
            XCTAssertTrue(phase.canStartAttempt)
        }
        for phase: FirmwareFlashPhase in [.idle, .validating, .waitingForDevice, .erasingDataFlash,
            .erasingCodeFlash, .flashing, .awaitingRuntimeVerification, .verifyingRuntime, .success] {
            XCTAssertFalse(phase.canStartAttempt)
        }
    }

    private func recordedToolCalls(in directory: URL) throws -> String {
        let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".calls") }
        return try paths.map { try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) }.joined()
    }

    actor ValidationGate {
        private var pending: [URL: CheckedContinuation<FirmwareImageDescriptor, Error>] = [:]
        private var started: Set<URL> = []
        private var waiters: [URL: CheckedContinuation<Void, Never>] = [:]

        func validate(_ url: URL) async throws -> FirmwareImageDescriptor {
            try await withCheckedThrowingContinuation { continuation in
                pending[url] = continuation
                started.insert(url)
                waiters.removeValue(forKey: url)?.resume()
            }
        }

        func waitUntilStarted(_ url: URL) async {
            if started.contains(url) { return }
            await withCheckedContinuation { waiters[url] = $0 }
        }

        func complete(_ url: URL) throws {
            let descriptor = try FirmwareImageValidator.validate(url: url)
            pending.removeValue(forKey: url)?.resume(returning: descriptor)
        }

        func fail(_ url: URL) {
            pending.removeValue(forKey: url)?.resume(throwing: FirmwareImageValidationError.unreadable)
        }
    }

    @MainActor
    func testOldReadFailureCannotFailNewValidation() async throws {
        let gate = ValidationGate()
        let first = try temporaryHEX(byte: 1)
        let second = try temporaryHEX(byte: 2)
        let (bundle, directory) = try temporaryToolBundle()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
            try? FileManager.default.removeItem(at: directory)
        }
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle, validateImage: { url, _ in try await gate.validate(url) })
        flasher.selectCustomFirmware(at: first)
        let oldTask = try XCTUnwrap(flasher.validationTask)
        await gate.waitUntilStarted(first)
        flasher.cancelSafely()
        flasher.selectCustomFirmware(at: second)
        let currentTask = try XCTUnwrap(flasher.validationTask)
        await gate.waitUntilStarted(second)

        await gate.fail(first)
        await oldTask.value
        XCTAssertEqual(flasher.phase, .validating)
        XCTAssertNotNil(flasher.validationTask)
        XCTAssertFalse(flasher.logLines.contains { $0.contains("无法读取") })

        try await gate.complete(second)
        await currentTask.value
        XCTAssertEqual(flasher.phase, .ready)
        XCTAssertEqual(flasher.selectedFirmware?.url, second)
        XCTAssertNil(flasher.validationTask)
    }

    @MainActor
    func testStartFlashingLocksFileBeforeStagingTaskRuns() async throws {
        let first = try temporaryHEX(byte: 1)
        let second = try temporaryHEX(byte: 2)
        let (bundle, directory) = try temporaryToolBundle()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
            try? FileManager.default.removeItem(at: directory)
        }
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle)
        flasher.selectCustomFirmware(at: first)
        await flasher.validationTask?.value
        XCTAssertEqual(flasher.phase, .ready)
        let selected = try XCTUnwrap(flasher.selectedFirmware)

        flasher.startFlashing()
        let flashing = try XCTUnwrap(flasher.flashTask)
        XCTAssertTrue(flasher.phase.isBusy, "Staging must lock selection immediately, before an async task runs")
        flasher.selectCustomFirmware(at: second)
        XCTAssertEqual(flasher.selectedFirmware, selected)

        // No ISP process may run: cancel on the same actor before the task starts.
        flasher.cancelSafely()
        flashing.cancel() // Also clean up the pre-fix .ready path if this regression goes red.
        flasher.validationTask?.cancel()
        await flashing.value
        await flasher.validationTask?.value
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
        XCTAssertEqual(flasher.phase, .cancelled)
        XCTAssertNil(flasher.flashTask)
    }

    @MainActor
    func testCancellationAfterDetectionDoesNotReportEraseOrLaunchEraseCommand() async throws {
        let image = try temporaryHEX(byte: 1)
        let (bundle, directory) = try temporaryToolBundle(infoSucceeds: true)
        defer {
            try? FileManager.default.removeItem(at: image)
            try? FileManager.default.removeItem(at: directory)
        }
        let flasher = AhaKeyFirmwareFlasher(bundle: bundle)
        flasher.selectCustomFirmware(at: image)
        await flasher.validationTask?.value
        XCTAssertEqual(flasher.phase, .ready)
        let observation = flasher.$chipInfo.dropFirst().sink { info in
            if info.contains("CH582") { flasher.cancelSafely() }
        }
        defer { observation.cancel() }
        flasher.startFlashing()
        await flasher.flashTask?.value
        XCTAssertEqual(flasher.phase, .cancelled)
        XCTAssertFalse(flasher.hasStartedDestructiveOperation)
        XCTAssertFalse(flasher.logLines.contains { $0.contains("开始清空") || $0.contains("恢复建议") })
        let receipts = try FileManager.default.subpathsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".calls") }
        XCTAssertEqual(receipts.count, 1)
        let calls = try String(contentsOf: directory.appendingPathComponent(try XCTUnwrap(receipts.first)), encoding: .utf8)
        XCTAssertEqual(calls, "--usb info --chip CH582\n", "Only the isolated info command may execute")
    }

    private func temporaryToolBundle(infoSucceeds: Bool = false) throws -> (Bundle, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.ahakey.flasher</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>".utf8)
            .write(to: contents.appendingPathComponent("Info.plist"))
        for architecture in ["arm64", "x86_64"] {
            let tool = contents.appendingPathComponent("Resources/FirmwareFlasher/tools/\(architecture)/wchisp")
            try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
            let script = infoSucceeds ? "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$0.calls\"\ncase \"$*\" in\n  '--usb info --chip CH582') printf 'Chip: CH582\\n'; exit 0;;\n  *) exit 9;;\nesac\n" : "#!/bin/sh\nexit 1\n"
            try Data(script.utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
        return (try XCTUnwrap(Bundle(url: root)), root)
    }

    @MainActor
    func testCancelledValidationCannotReplaceNewSelectionStateOrTask() async throws {
        let gate = ValidationGate()
        let first = try temporaryHEX(byte: 1)
        let second = try temporaryHEX(byte: 2)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let flasher = AhaKeyFirmwareFlasher(validateImage: { url, _ in try await gate.validate(url) })
        flasher.selectCustomFirmware(at: first)
        let oldTask = try XCTUnwrap(flasher.validationTask)
        await gate.waitUntilStarted(first)
        flasher.cancelSafely()
        flasher.selectCustomFirmware(at: second)
        let currentTask = try XCTUnwrap(flasher.validationTask)
        await gate.waitUntilStarted(second)

        try await gate.complete(first)
        await oldTask.value

        XCTAssertEqual(flasher.phase, .validating, "Cancelled file A must not cancel file B's validation UI")
        XCTAssertNotNil(flasher.validationTask, "A must not clear B's cancellation handle")
        XCTAssertNil(flasher.selectedFirmware)
        flasher.cancelSafely()
        try await gate.complete(second)
        await currentTask.value
    }

    private func temporaryHEX(byte: UInt8) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("hex")
        let line = String(format: ":01000000%02X%02X\n:00000001FF\n", byte, UInt8(0 &- (1 + byte)))
        try Data(line.utf8).write(to: url)
        return url
    }
}
