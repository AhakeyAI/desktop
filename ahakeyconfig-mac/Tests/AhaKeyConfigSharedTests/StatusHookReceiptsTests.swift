import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class StatusHookReceiptsTests: XCTestCase {
    func testReceiptRequiresCurrentEntryConfigAndClient() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = CodexHookInstallation(directory: root).entryURL
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: entry)
        let receipts = StatusHookReceipts(directory: root)
        let configuration = root.appendingPathComponent("example.json")
        try Data("one".utf8).write(to: configuration)
        try receipts.confirm(client: .copilot, configuration: configuration)
        try receipts.confirm(client: .workBuddy, configuration: configuration)
        receipts.eventRecorder(client: .copilot, executablePath: "/tmp/old-hook")()
        XCTAssertFalse(receipts.isVerified(client: .copilot, configuration: configuration))

        let record = receipts.eventRecorder(client: .copilot, executablePath: entry.path, host: .orca)
        record()
        XCTAssertTrue(receipts.isVerified(client: .copilot, configuration: configuration))
        XCTAssertEqual(receipts.status(client: .copilot, configurations: [configuration])?.hosts, [.orca])
        receipts.eventRecorder(client: .copilot, executablePath: entry.path, host: .t3Code)()
        XCTAssertEqual(receipts.status(client: .copilot, configurations: [configuration])?.hosts, [.orca, .t3Code])
        XCTAssertFalse(receipts.isVerified(client: .workBuddy, configuration: configuration))
        try Data("two".utf8).write(to: configuration)
        XCTAssertFalse(receipts.isVerified(client: .copilot, configuration: configuration))
        XCTAssertEqual(receipts.status(client: .copilot, configurations: [configuration])?.hosts, [])
        try receipts.confirm(client: .copilot, configuration: configuration)
        record()
        XCTAssertFalse(receipts.isVerified(client: .copilot, configuration: configuration))

        receipts.eventRecorder(client: .copilot, executablePath: entry.path)()
        XCTAssertTrue(receipts.isVerified(client: .copilot, configuration: configuration))
        try receipts.confirm(client: .workBuddy, configuration: configuration)
        let stale = receipts.eventRecorder(client: .workBuddy, executablePath: entry.path)
        stale()
        XCTAssertTrue(receipts.isVerified(client: .workBuddy, configuration: configuration))
        try FileManager.default.removeItem(at: entry)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/false"), to: entry)
        try receipts.confirmEntryUpgrade(XCTUnwrap(CodexHookInstallation.EntryIdentity(at: entry)))
        stale()
        XCTAssertFalse(receipts.isVerified(client: .workBuddy, configuration: configuration))
        receipts.eventRecorder(client: .workBuddy, executablePath: entry.path)()
        XCTAssertTrue(receipts.isVerified(client: .workBuddy, configuration: configuration))
        receipts.clear(client: .copilot)
        XCTAssertFalse(receipts.isVerified(client: .copilot, configuration: configuration))
    }

    func testOnlyRecognizedLauncherEvidenceGetsAHostLabel() {
        XCTAssertEqual(HookExecutionHost.identify(ancestorBundles: ["Codex Helper.app", "Codex.app"],
                                                   environment: [:]), .codexDesktop)
        XCTAssertEqual(HookExecutionHost.identify(ancestorBundles: ["LobeHub.app"], environment: [:]), .lobeHub)
        XCTAssertEqual(HookExecutionHost.identify(ancestorBundles: ["T3 Code.app"], environment: [:]), .t3Code)
        XCTAssertEqual(HookExecutionHost.identify(ancestorBundles: [], environment: [
            "ORCA_WORKTREE_ID": "fixture", "ORCA_TERMINAL_HANDLE": "fixture",
        ]), .orca)
        XCTAssertEqual(HookExecutionHost.identify(ancestorBundles: ["Other.app"],
                                                   environment: ["CODEX_HOME": "/tmp/Orca"]), .unidentified)
    }
}
