import XCTest
@testable import AhaKeyConfigShared

final class ApprovalAutomationLifecycleTests: XCTestCase {
    struct Fixture {
        let directory: URL, control: URL, codex: URL, kimi: URL
        init(codex: String = "approval_policy = \"on-request\" # user\n", kimi: String = "default_yolo = false # user\n") throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            control = directory.appendingPathComponent("control")
            self.codex = directory.appendingPathComponent("codex.toml"); self.kimi = directory.appendingPathComponent("kimi.toml")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(codex.utf8).write(to: self.codex); try Data(kimi.utf8).write(to: self.kimi)
        }
        func revoke(_ client: ApprovalAutomationControl.Client? = nil) -> Bool {
            ApprovalAutomationControl.revoke(client, directory: control, codexURL: codex, kimiURL: kimi)
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
    func testKimiRequestMigrationOnlyTouchesOwnedLoaderAndIsIdempotent() {
        let request = #"sock.sendall(b'{"cmd":"approval_status"}\n')"#
        let before = "# unrelated: " + request + "\n_AHAKEY_SOCKET_PATH = \"/tmp/ahakey.sock\"\ndef _load_ahakey_override_uncached() -> dict[str, object] | None:\n    " + request + "\n\ndef get_ahakey_approval_override(*, force_refresh=False):\n    " + request + "\n"
        let result = KimiApprovalRequestMigration.upgradeOwnedHelper(in: before)
        XCTAssertEqual(result.components(separatedBy: "kimi_approval_status").count - 1, 1)
        XCTAssertEqual(result.components(separatedBy: #"{"cmd":"approval_status"}"#).count - 1, 2)
        XCTAssertEqual(KimiApprovalRequestMigration.upgradeOwnedHelper(in: result), result)
        XCTAssertEqual(KimiApprovalRequestMigration.upgradeOwnedHelper(in: request), request)
        XCTAssertEqual(KimiApprovalRequestMigration.upgradeOwnedHelper(in: before.replacingOccurrences(of: "def get_ahakey_approval_override", with: "def other")), before.replacingOccurrences(of: "def get_ahakey_approval_override", with: "def other"))
    }
    func testStopRestoresOnlyOwnedAutoTokensAndKeepsCurrentUnrelatedChanges() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertEqual(CodexConfigLeverSync.apply(switchStateAuto: true, configURL: f.codex, controlDirectory: f.control), .replaced)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: f.kimi, controlDirectory: f.control), .updated)
        let codexCurrent = try String(contentsOf: f.codex) + "model = \"keep-new-user-value\"\n"
        let kimiCurrent = try String(contentsOf: f.kimi) + "[plugin]\ndefault_yolo = true\n"
        try codexCurrent.write(to: f.codex, atomically: true, encoding: .utf8)
        try kimiCurrent.write(to: f.kimi, atomically: true, encoding: .utf8)
        XCTAssertTrue(f.revoke())
        XCTAssertEqual(try String(contentsOf: f.codex), codexCurrent.replacingOccurrences(of: "\"never\"", with: "\"on-request\""))
        XCTAssertEqual(try String(contentsOf: f.kimi), "default_yolo = false # user\n[plugin]\ndefault_yolo = true\n")
        XCTAssertEqual(CodexConfigLeverSync.apply(switchStateAuto: true, configURL: f.codex, controlDirectory: f.control), .automationDisabled)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: f.kimi, controlDirectory: f.control), .disabled)
    }
    func testPreexistingUserAutoValuesAreNotClaimedOrReverted() throws {
        let f = try Fixture(codex: "approval_policy = \"never\"\n", kimi: "default_yolo = true\n"); defer { f.remove() }
        XCTAssertEqual(CodexConfigLeverSync.apply(switchStateAuto: true, configURL: f.codex, controlDirectory: f.control), .alreadyDesired)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: f.kimi, controlDirectory: f.control), .unchanged)
        XCTAssertTrue(f.revoke())
        XCTAssertEqual(try String(contentsOf: f.codex), "approval_policy = \"never\"\n")
        XCTAssertEqual(try String(contentsOf: f.kimi), "default_yolo = true\n")
    }
    func testClientRevocationDoesNotDisablePeersAndGlobalPauseCannotBeOverriddenByClientResume() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertTrue(f.revoke(.codex))
        XCTAssertFalse(ApprovalAutomationControl.isEnabled(.codex, directory: f.control))
        XCTAssertTrue(ApprovalAutomationControl.isEnabled(.kimi, directory: f.control))
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: f.kimi, controlDirectory: f.control), .updated)
        XCTAssertTrue(f.revoke())
        XCTAssertTrue(ApprovalAutomationControl.resume(.codex, directory: f.control))
        XCTAssertFalse(ApprovalAutomationControl.isEnabled(.codex, directory: f.control))
        XCTAssertTrue(ApprovalAutomationControl.resume(directory: f.control))
        XCTAssertTrue(ApprovalAutomationControl.isEnabled(.codex, directory: f.control))
    }
    func testUserPolicyChangeAfterAutoIsPreserved() throws {
        let f = try Fixture(); defer { f.remove() }
        _ = CodexConfigLeverSync.apply(switchStateAuto: true, configURL: f.codex, controlDirectory: f.control)
        try "approval_policy = \"on-failure\"\n".write(to: f.codex, atomically: true, encoding: .utf8)
        XCTAssertTrue(f.revoke(.codex))
        XCTAssertEqual(try String(contentsOf: f.codex), "approval_policy = \"on-failure\"\n")
    }
    func testKimiPreservesMultilineStringsNestedKeysCommentsAndCRLF() throws {
        let input = "prompt = '''\r\ndefault_yolo = true\r\n'''\r\ndefault_yolo  =  false  # custom\r\n[plugin]\r\ndefault_yolo = false\r\n"
        let f = try Fixture(kimi: input); defer { f.remove() }
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: f.kimi, controlDirectory: f.control), .updated)
        let expected = input.replacingOccurrences(of: "default_yolo  =  false", with: "default_yolo  =  true")
        XCTAssertEqual(try String(contentsOf: f.kimi), expected)
        XCTAssertTrue(f.revoke(.kimi))
        XCTAssertEqual(try String(contentsOf: f.kimi), input)
    }
    func testKimiMissingRootInsertsBeforeTableAndNeverReplacesNestedKey() throws {
        let f = try Fixture(kimi: "# user\n[plugin]\ndefault_yolo = false\n"); defer { f.remove() }
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: f.kimi, controlDirectory: f.control), .updated)
        XCTAssertEqual(try String(contentsOf: f.kimi), "# user\ndefault_yolo = true\n[plugin]\ndefault_yolo = false\n")
    }
    func testMalformedDuplicateOrNonBooleanKimiRemainsByteIdentical() throws {
        for text in ["default_yolo = true\ndefault_yolo = false\n", "default_yolo = { value = true }\n", "prompt = '''broken\ndefault_yolo = false\n", "default_yolo = \"true\"\n"] {
            let f = try Fixture(kimi: text); defer { f.remove() }
            XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: f.kimi, controlDirectory: f.control), .invalid)
            XCTAssertEqual(try String(contentsOf: f.kimi), text)
            XCTAssertFalse(FileManager.default.fileExists(atPath: KimiConfigPolicySync.leaseURL(f.kimi).path))
        }
    }
    func testLegacyOwnedKimiCommentCanBeReleasedWithoutRestoringOldBackup() throws {
        let f = try Fixture(kimi: "default_yolo = true  # AhaKey: dial auto; run /reload in Kimi after changing dial\n[other]\nvalue = 9\n"); defer { f.remove() }
        XCTAssertTrue(f.revoke(.kimi))
        XCTAssertTrue(try String(contentsOf: f.kimi).hasPrefix("default_yolo = false"))
        XCTAssertTrue(try String(contentsOf: f.kimi).contains("value = 9"))
    }
    func testMissingControlReadDoesNotCreateFilesAndCorruptControlFailsClosed() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertTrue(ApprovalAutomationControl.isEnabled(.codex, directory: f.control))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.control.path))
        try Data([1]).write(to: f.control)
        XCTAssertFalse(ApprovalAutomationControl.isEnabled(.codex, directory: f.control))
    }
    func testConcurrentLateAutoWritersCannotUndoStop() throws {
        let f = try Fixture(); defer { f.remove() }
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            if index == 10 { _ = f.revoke() }
            else { _ = CodexConfigLeverSync.apply(switchStateAuto: true, configURL: f.codex, controlDirectory: f.control) }
        }
        XCTAssertFalse(ApprovalAutomationControl.isEnabled(.codex, directory: f.control))
        XCTAssertFalse(try String(contentsOf: f.codex).contains("\"never\""))
    }
}
