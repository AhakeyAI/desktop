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

        let record = receipts.eventRecorder(client: .copilot, executablePath: entry.path)
        record()
        XCTAssertTrue(receipts.isVerified(client: .copilot, configuration: configuration))
        XCTAssertFalse(receipts.isVerified(client: .workBuddy, configuration: configuration))
        try Data("two".utf8).write(to: configuration)
        XCTAssertFalse(receipts.isVerified(client: .copilot, configuration: configuration))
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
}
