import XCTest
@testable import AhaKeyConfigAgent

/// 15K-J：Codex 审批策略兼容（`approval_policy` 只允许 `on-request` / `never`）。
///
/// 深模块 seam：`CodexConfigLeverSync.ApprovalPolicy`（typed allowlist）+
/// `apply(policy:configURL:)`（可注入 fixture URL）。所有测试都在临时目录运行，
/// **绝不触碰**用户真实 `~/.codex/config.toml`。
final class CodexConfigLeverSyncTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5j-codex-lever-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    // MARK: - fixture 帮助

    private typealias Policy = CodexConfigLeverSync.ApprovalPolicy

    private func writeFixture(_ text: String, name: String = "config.toml") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func writeFixture(bytes: [UInt8], name: String = "config.toml") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func text(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func bytes(of url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AhaKeyAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // ahakeyconfig-mac
    }

    // MARK: - 1. 冻结语义与 typed allowlist

    func testPolicyAllowlistIsExactlyOnRequestAndNever() {
        XCTAssertEqual(Policy.allCases.map(\.rawValue).sorted(), ["never", "on-request"])
        XCTAssertNil(Policy(rawValue: "untrusted"), "untrusted 必须不可表示")
        for policy in Policy.allCases {
            XCTAssertFalse(policy.configLine.contains("untrusted"))
        }
        XCTAssertEqual(Policy.never.configLine, "approval_policy = \"never\"")
        XCTAssertEqual(Policy.onRequest.configLine, "approval_policy = \"on-request\"")
    }

    func testLeverMapsToFrozenSemantics() {
        XCTAssertEqual(Policy.forLever(switchStateAuto: true), .never, "自动档 → never")
        XCTAssertEqual(Policy.forLever(switchStateAuto: false), .onRequest, "手动档 → on-request")
    }

    /// 红能力负对照：旧映射（C5IR8 前）手动档产出 `untrusted`，该值必须被 allowlist 拒绝。
    func testLegacyUntrustedMappingFailsTheFrozenAllowlist() {
        XCTAssertEqual(Self.legacyDesiredValue(switchStateAuto: false), "untrusted")
        XCTAssertEqual(Self.legacyDesiredValue(switchStateAuto: true), "never")
        XCTAssertNil(
            Policy(rawValue: Self.legacyDesiredValue(switchStateAuto: false)),
            "旧映射产出的取值必须被冻结 allowlist 拒绝"
        )
        XCTAssertNotNil(Policy(rawValue: Self.legacyDesiredValue(switchStateAuto: true)))
    }

    /// 旧产品映射的忠实副本（只用于负对照，不参与产品路径）。
    private static func legacyDesiredValue(switchStateAuto: Bool) -> String {
        switchStateAuto ? "never" : "untrusted"
    }

    // MARK: - 2. untrusted 迁移（红→绿核心）

    func testExistingUntrustedIsRewrittenForManualLever() throws {
        let url = try writeFixture(
            "approval_policy = \"untrusted\"\nmodel = \"gpt-5\"\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"
        )
        let outcome = CodexConfigLeverSync.apply(policy: .forLever(switchStateAuto: false), configURL: url)
        XCTAssertEqual(outcome, .replaced)
        let result = try text(of: url)
        XCTAssertEqual(
            result,
            "approval_policy = \"on-request\"\nmodel = \"gpt-5\"\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"
        )
        XCTAssertFalse(result.contains("untrusted"))
    }

    func testExistingUntrustedIsRewrittenForAutoLever() throws {
        let url = try writeFixture("approval_policy = \"untrusted\"\n\n[hooks]\n")
        let outcome = CodexConfigLeverSync.apply(policy: .forLever(switchStateAuto: true), configURL: url)
        XCTAssertEqual(outcome, .replaced)
        XCTAssertEqual(try text(of: url), "approval_policy = \"never\"\n\n[hooks]\n")
    }

    // MARK: - 3. 合法值精确切换 + 幂等零字节变化

    func testLegalValueIsIdempotentWithoutByteChanges() throws {
        let manual = try writeFixture("approval_policy = \"on-request\"\nmodel = \"gpt-5\"\n")
        let before = try bytes(of: manual)
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .onRequest, configURL: manual), .alreadyDesired)
        XCTAssertEqual(try bytes(of: manual), before, "目标相同必须零字节变化")

        let auto = try writeFixture("approval_policy = \"never\"\nmodel = \"gpt-5\"\n")
        let autoBefore = try bytes(of: auto)
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .never, configURL: auto), .alreadyDesired)
        XCTAssertEqual(try bytes(of: auto), autoBefore)
    }

    func testLegalValueSwitchesExactlyBetweenTheTwoStates() throws {
        let url = try writeFixture("approval_policy = \"never\"\nmodel = \"gpt-5\"\n")
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .onRequest, configURL: url), .replaced)
        XCTAssertEqual(try text(of: url), "approval_policy = \"on-request\"\nmodel = \"gpt-5\"\n")
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .never, configURL: url), .replaced)
        XCTAssertEqual(try text(of: url), "approval_policy = \"never\"\nmodel = \"gpt-5\"\n")
    }

    // MARK: - 4. 缺键插入位置

    func testMissingKeyIsInsertedBeforeFirstSection() throws {
        let url = try writeFixture("model = \"gpt-5\"\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n")
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .onRequest, configURL: url), .inserted)
        XCTAssertEqual(
            try text(of: url),
            "model = \"gpt-5\"\n\napproval_policy = \"on-request\"\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"
        )
    }

    func testMissingKeyWithoutAnySectionIsAppended() throws {
        let url = try writeFixture("model = \"gpt-5\"")
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .never, configURL: url), .inserted)
        XCTAssertEqual(try text(of: url), "model = \"gpt-5\"\napproval_policy = \"never\"")
    }

    // MARK: - 5. 保留其它内容（注释 / 空行 / 键序 / sections / 尾换行）

    func testPreservesCommentsBlankLinesAndSectionOrdering() throws {
        let fixture = """
        # Codex config (kept)
        model = "gpt-5"

        # 审批策略：拨杆写入
        approval_policy = "never"

        [projects."/a"]
        trust_level = "trusted"

        [hooks]
        # keep me

        """
        let url = try writeFixture(fixture)
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .onRequest, configURL: url), .replaced)
        let expected = fixture.replacingOccurrences(
            of: "approval_policy = \"never\"",
            with: "approval_policy = \"on-request\""
        )
        XCTAssertEqual(try text(of: url), expected)
        // 再次应用必须幂等。
        let after = try bytes(of: url)
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .onRequest, configURL: url), .alreadyDesired)
        XCTAssertEqual(try bytes(of: url), after)
    }

    // MARK: - 6. fail-safe 边界

    func testMissingConfigIsReportedAndNotCreated() {
        let url = root.appendingPathComponent("absent.toml")
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .onRequest, configURL: url), .missingConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "缺文件不得被创建")
    }

    func testNonUTF8ConfigIsLeftUntouched() throws {
        let url = try writeFixture(bytes: [0x61, 0x70, 0x70, 0xFF, 0xFE, 0x0A])
        let before = try bytes(of: url)
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .never, configURL: url), .unreadableConfig)
        XCTAssertEqual(try bytes(of: url), before, "非 UTF-8 必须原样保留")
    }

    func testWriteFailureIsTypedAndLeavesOriginalContent() throws {
        try XCTSkipIf(geteuid() == 0, "root 会绕过只读目录")
        let url = try writeFixture("approval_policy = \"never\"\nmodel = \"gpt-5\"\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        }
        XCTAssertEqual(CodexConfigLeverSync.apply(policy: .onRequest, configURL: url), .writeFailed)
        XCTAssertEqual(try text(of: url), "approval_policy = \"never\"\nmodel = \"gpt-5\"\n")
    }

    // MARK: - 7. 生产路径不得被测试触碰

    func testProductionConfigURLPointsAtRealHomeCodexConfig() {
        let url = CodexConfigLeverSync.productionConfigURL
        XCTAssertTrue(url.path.hasSuffix("/.codex/config.toml"))
        XCTAssertFalse(url.path.hasPrefix(root.path), "生产路径不得落在测试临时目录")
    }

    // MARK: - 8. 两个生产调用点必须走同一 typed seam

    func testBothProductionCallsitesRouteThroughTypedSeam() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Agent/CodexHookHandler.swift"),
            encoding: .utf8
        )
        let callsites = source
            .components(separatedBy: .newlines)
            .filter { $0.contains("CodexConfigLeverSync.apply(") }
        XCTAssertEqual(callsites.count, 2, "CodexSessionStart / CodexPermissionRequest 各一个调用点")
        for line in callsites {
            XCTAssertTrue(
                line.contains("switchStateAuto:"),
                "调用点必须经 apply(switchStateAuto:) seam，实得：\(line)"
            )
        }
        XCTAssertFalse(Self.strippingComments(source).contains("untrusted"))
    }

    // MARK: - 9. 产品可执行代码不得存在 untrusted / 越界 approval_policy 写入路径

    func testProductSourcesHaveNoUntrustedApprovalPolicyWritePath() throws {
        let sourcesRoot = packageRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        )
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let relative = String(url.path.dropFirst(packageRoot.path.count + 1))
            let code = Self.strippingComments(try String(contentsOf: url, encoding: .utf8))
            XCTAssertFalse(
                code.contains("\"untrusted\""),
                "\(relative)：可执行代码不得包含 untrusted 字面量"
            )
            XCTAssertFalse(
                code.contains("untrusted"),
                "\(relative)：可执行代码不得出现 untrusted"
            )
            if !relative.hasSuffix("Sources/Agent/CodexConfigLeverSync.swift") {
                XCTAssertFalse(
                    code.contains("approval_policy"),
                    "\(relative)：approval_policy 只能由 CodexConfigLeverSync 写入"
                )
            }
        }
        XCTAssertGreaterThan(scanned, 10, "Sources 扫描面异常：仅 \(scanned) 个 .swift")
    }

    /// 朴素注释剥离：去掉整行注释与行尾 `//` 注释（足以覆盖本仓 Sources 的写法）。
    private static func strippingComments(_ source: String) -> String {
        source
            .components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                    || trimmed.hasPrefix("*") || trimmed.hasPrefix("*/") {
                    return ""
                }
                if let range = line.range(of: "//") {
                    return String(line[line.startIndex..<range.lowerBound])
                }
                return line
            }
            .joined(separator: "\n")
    }
}
