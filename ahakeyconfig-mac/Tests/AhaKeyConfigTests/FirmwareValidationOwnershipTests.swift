import Foundation
import XCTest
@testable import AhaKeyConfig

final class FirmwareValidationOwnershipTests: XCTestCase {
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

    private func temporaryToolBundle() throws -> (Bundle, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.ahakey.flasher</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>".utf8)
            .write(to: contents.appendingPathComponent("Info.plist"))
        for architecture in ["arm64", "x86_64"] {
            let tool = contents.appendingPathComponent("Resources/FirmwareFlasher/tools/\(architecture)/wchisp")
            try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 1\n".utf8).write(to: tool)
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
