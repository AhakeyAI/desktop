import XCTest
@testable import AhaKeyConfigAgent

/// C5JR1：Codex 审批策略兼容（字节保真 TOML 定位 + typed fail-closed）。
///
/// 所有测试只经 `CodexConfigLeverSync.apply(switchStateAuto:configURL:)` 这一条 seam
/// （raw-policy 写入口在产品里是 `private`，编译期不可达），并在临时目录 fixture 上运行，
/// **绝不触碰**用户真实 `~/.codex/config.toml`。
///
/// 永久反例是表驱动的：每行断言 Outcome + 精确字节（成功行）或零字节变化（fail-closed 行），
/// 覆盖 CRLF/CR、非规范空格、行尾注释、多行 basic/literal string、跨行 array / inline table、
/// 空文件、重复 key 与未闭合输入。
final class CodexConfigLeverSyncTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5jr1-codex-lever-\(UUID().uuidString)", isDirectory: true)
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
    private typealias Outcome = CodexConfigLeverSync.Outcome

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

    private func apply(auto: Bool, to url: URL) -> Outcome {
        CodexConfigLeverSync.apply(switchStateAuto: auto, configURL: url)
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AhaKeyAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // ahakeyconfig-mac
    }

    // MARK: - 冻结语义与 typed allowlist

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

    // MARK: - 永久表驱动反例

    private enum FailureKind {
        case duplicate
        case unsupported
    }

    private enum Expectation {
        /// Outcome 精确等于给定值，且文件字节**零变化**。
        case unchanged(Outcome)
        /// 必须 typed fail-closed（重复 key / unsupported），且文件字节**零变化**。
        case failClosed(FailureKind)
        /// Outcome 精确等于给定值，且文件字节精确等于给定文本。
        case result(Outcome, String)
    }

    private struct Row {
        let id: String
        let input: String
        let auto: Bool
        let expectation: Expectation
    }

    private static let rows: [Row] = [
        // ---- 基本迁移 ----
        Row(id: "lf.untrusted.manual",
            input: "approval_policy = \"untrusted\"\nmodel = \"gpt-5\"\n",
            auto: false,
            expectation: .result(.replaced, "approval_policy = \"on-request\"\nmodel = \"gpt-5\"\n")),
        Row(id: "lf.untrusted.auto",
            input: "approval_policy = \"untrusted\"\nmodel = \"gpt-5\"\n",
            auto: true,
            expectation: .result(.replaced, "approval_policy = \"never\"\nmodel = \"gpt-5\"\n")),
        Row(id: "lf.legal.toggle.manual",
            input: "approval_policy = \"never\"\nmodel = \"gpt-5\"\n",
            auto: false,
            expectation: .result(.replaced, "approval_policy = \"on-request\"\nmodel = \"gpt-5\"\n")),
        Row(id: "lf.no-trailing-newline.manual",
            input: "approval_policy = \"untrusted\"",
            auto: false,
            expectation: .result(.replaced, "approval_policy = \"on-request\"")),

        // ---- 换行保真：CRLF / CR ----
        Row(id: "crlf.untrusted.manual",
            input: "# c\r\napproval_policy = \"untrusted\"\r\nmodel = \"gpt-5\"\r\n",
            auto: false,
            expectation: .result(.replaced, "# c\r\napproval_policy = \"on-request\"\r\nmodel = \"gpt-5\"\r\n")),
        Row(id: "cr.untrusted.auto",
            input: "approval_policy = \"untrusted\"\rmodel = \"gpt-5\"\r",
            auto: true,
            expectation: .result(.replaced, "approval_policy = \"never\"\rmodel = \"gpt-5\"\r")),
        Row(id: "crlf.same-value.auto",
            input: "approval_policy = \"never\"\r\nmodel = \"x\"\r\n",
            auto: true,
            expectation: .unchanged(.alreadyDesired)),

        // ---- 幂等：非规范空格 / 引号风格 ----
        Row(id: "nospace.same-value.auto",
            input: "approval_policy=\"never\"\n",
            auto: true,
            expectation: .unchanged(.alreadyDesired)),
        Row(id: "nospace.same-value.manual",
            input: "approval_policy=\"never\"\n",
            auto: false,
            expectation: .result(.replaced, "approval_policy=\"on-request\"\n")),
        Row(id: "nospace.untrusted.manual",
            input: "approval_policy=\"untrusted\"\n",
            auto: false,
            expectation: .result(.replaced, "approval_policy=\"on-request\"\n")),
        Row(id: "literal-quote.same-value.auto",
            input: "approval_policy = 'never'\n",
            auto: true,
            expectation: .unchanged(.alreadyDesired)),
        Row(id: "literal-quote.switch.manual",
            input: "approval_policy = 'never'\n",
            auto: false,
            expectation: .result(.replaced, "approval_policy = \"on-request\"\n")),
        Row(id: "quoted-key.mixed-spacing.manual",
            input: "\"approval_policy\"  =  \"untrusted\"\t# c\n",
            auto: false,
            expectation: .result(.replaced, "\"approval_policy\"  =  \"on-request\"\t# c\n")),

        // ---- 行尾注释 ----
        Row(id: "comment.same-value.auto",
            input: "approval_policy = \"never\" # local\n",
            auto: true,
            expectation: .unchanged(.alreadyDesired)),
        Row(id: "comment.switch.manual",
            input: "approval_policy = \"never\" # local\n",
            auto: false,
            expectation: .result(.replaced, "approval_policy = \"on-request\" # local\n")),
        Row(id: "comment.untrusted.manual",
            input: "approval_policy = \"untrusted\" # keep me\r\n",
            auto: false,
            expectation: .result(.replaced, "approval_policy = \"on-request\" # keep me\r\n")),

        // ---- 多行字符串里的假 [section] / 假 approval_policy ----
        Row(id: "multiline-basic-string.fake.manual",
            input: "banner = \"\"\"\n[fake]\napproval_policy = \"untrusted\"\n\"\"\"\napproval_policy = \"untrusted\"\n[real]\n",
            auto: false,
            expectation: .result(
                .replaced,
                "banner = \"\"\"\n[fake]\napproval_policy = \"untrusted\"\n\"\"\"\napproval_policy = \"on-request\"\n[real]\n"
            )),
        Row(id: "multiline-literal-string.fake.auto",
            input: "banner = '''\n[fake]\napproval_policy = 'untrusted'\n'''\napproval_policy = \"untrusted\"\n[real]\n",
            auto: true,
            expectation: .result(
                .replaced,
                "banner = '''\n[fake]\napproval_policy = 'untrusted'\n'''\napproval_policy = \"never\"\n[real]\n"
            )),
        Row(id: "multiline-string.only-fake-key.manual",
            input: "note = \"\"\"\napproval_policy = \"untrusted\"\n\"\"\"\n[real]\n",
            auto: false,
            expectation: .result(
                .inserted,
                "note = \"\"\"\napproval_policy = \"untrusted\"\n\"\"\"\napproval_policy = \"on-request\"\n[real]\n"
            )),

        // ---- 跨行 array / inline table ----
        Row(id: "multiline-array.fake-section.manual",
            input: "items = [\n  \"[fake]\",\n  \"x\",\n]\n[real]\n",
            auto: false,
            expectation: .result(
                .inserted,
                "items = [\n  \"[fake]\",\n  \"x\",\n]\napproval_policy = \"on-request\"\n[real]\n"
            )),
        Row(id: "multiline-array.real-key.manual",
            input: "items = [\n  \"a\",\n]\napproval_policy = \"untrusted\"\n[real]\n",
            auto: false,
            expectation: .result(
                .replaced,
                "items = [\n  \"a\",\n]\napproval_policy = \"on-request\"\n[real]\n"
            )),
        Row(id: "crossline-inline-table.fake-section.manual",
            input: "t = {\n  a = \"[fake]\",\n}\n[real]\n",
            auto: false,
            expectation: .result(
                .inserted,
                "t = {\n  a = \"[fake]\",\n}\napproval_policy = \"on-request\"\n[real]\n"
            )),
        Row(id: "inline-table.inner-key-is-not-top-level.manual",
            input: "t = { approval_policy = \"untrusted\" }\napproval_policy = \"untrusted\"\n",
            auto: false,
            expectation: .result(
                .replaced,
                "t = { approval_policy = \"untrusted\" }\napproval_policy = \"on-request\"\n"
            )),

        // ---- 注释里的假内容 ----
        Row(id: "comment.fake-section.manual",
            input: "# [fake]\napproval_policy = \"untrusted\"\n",
            auto: false,
            expectation: .result(.replaced, "# [fake]\napproval_policy = \"on-request\"\n")),
        Row(id: "comment.fake-key.auto",
            input: "# approval_policy = \"untrusted\"\nmodel = \"x\"\n",
            auto: true,
            expectation: .result(.inserted, "# approval_policy = \"untrusted\"\nmodel = \"x\"\napproval_policy = \"never\"\n")),

        // ---- 缺键插入 ----
        Row(id: "missing.before-first-table.manual",
            input: "model = \"gpt-5\"\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n",
            auto: false,
            expectation: .result(
                .inserted,
                "model = \"gpt-5\"\n\napproval_policy = \"on-request\"\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"
            )),
        Row(id: "missing.crlf.before-first-table.auto",
            input: "model = \"gpt-5\"\r\n\r\n[projects.\"/x\"]\r\n",
            auto: true,
            expectation: .result(
                .inserted,
                "model = \"gpt-5\"\r\n\r\napproval_policy = \"never\"\r\n[projects.\"/x\"]\r\n"
            )),
        Row(id: "missing.cr.before-first-table.manual",
            input: "model = \"x\"\r[real]\r",
            auto: false,
            expectation: .result(.inserted, "model = \"x\"\rapproval_policy = \"on-request\"\r[real]\r")),
        Row(id: "missing.array-of-tables.auto",
            input: "[[products]]\nname = \"x\"\n",
            auto: true,
            expectation: .result(.inserted, "approval_policy = \"never\"\n[[products]]\nname = \"x\"\n")),
        Row(id: "missing.no-section.auto",
            input: "model = \"gpt-5\"\n",
            auto: true,
            expectation: .result(.inserted, "model = \"gpt-5\"\napproval_policy = \"never\"\n")),
        Row(id: "missing.no-trailing-newline.manual",
            input: "model = \"gpt-5\"",
            auto: false,
            expectation: .result(.inserted, "model = \"gpt-5\"\napproval_policy = \"on-request\"")),
        Row(id: "empty-file.manual",
            input: "",
            auto: false,
            expectation: .result(.inserted, "approval_policy = \"on-request\"\n")),
        Row(id: "comments-only.auto",
            input: "# nothing here\n",
            auto: true,
            expectation: .result(.inserted, "# nothing here\napproval_policy = \"never\"\n")),
        Row(id: "dotted-key-is-not-top-level.auto",
            input: "a.approval_policy = \"x\"\n",
            auto: true,
            expectation: .result(.inserted, "a.approval_policy = \"x\"\napproval_policy = \"never\"\n")),

        // ---- 歧义 / 重复 key ----
        Row(id: "duplicate-key.auto",
            input: "approval_policy = \"never\"\napproval_policy = \"on-request\"\n",
            auto: true,
            expectation: .unchanged(.duplicateKey)),
        Row(id: "in-table-key-is-not-duplicate.auto",
            input: "approval_policy = \"never\"\n[t]\napproval_policy = \"on-request\"\n",
            auto: true,
            expectation: .unchanged(.alreadyDesired)),

        // ---- 未闭合 / 非 scalar：零写 fail-closed ----
        Row(id: "unclosed.basic-string.auto",
            input: "approval_policy = \"never\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "unclosed.multiline-string.auto",
            input: "note = \"\"\"abc\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "unclosed.array.auto",
            input: "items = [1, 2\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "unclosed.inline-table.auto",
            input: "t = { a = 1\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "unclosed.table-header.auto",
            input: "[projects\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "nonscalar.number.auto",
            input: "approval_policy = 42\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "nonscalar.multiline-value.auto",
            input: "approval_policy = \"\"\"never\"\"\"\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "nonscalar.array-value.auto",
            input: "approval_policy = [\"never\"]\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
        Row(id: "trailing-junk.after-value.auto",
            input: "approval_policy = \"never\" junk\n",
            auto: true,
            expectation: .failClosed(.unsupported)),
    ]

    func testPermanentFixtureRows() throws {
        XCTAssertEqual(Self.rows.count, Set(Self.rows.map(\.id)).count, "row id 必须唯一")
        for row in Self.rows {
            let url = try writeFixture(row.input)
            let before = try bytes(of: url)
            let outcome = apply(auto: row.auto, to: url)

            switch row.expectation {
            case let .unchanged(expected):
                XCTAssertEqual(outcome, expected, "\(row.id)：Outcome 不符")
                XCTAssertEqual(try bytes(of: url), before, "\(row.id)：必须零字节变化")
            case let .failClosed(kind):
                switch (kind, outcome) {
                case (.duplicate, .duplicateKey), (.unsupported, .unsupportedSyntax):
                    break
                default:
                    XCTFail("\(row.id)：期望 fail-closed \(kind)，实得 \(outcome)")
                }
                XCTAssertEqual(try bytes(of: url), before, "\(row.id)：fail-closed 必须零字节变化")
            case let .result(expected, expectedText):
                XCTAssertEqual(outcome, expected, "\(row.id)：Outcome 不符")
                XCTAssertEqual(try text(of: url), expectedText, "\(row.id)：字节不符")
            }
        }
    }

    // MARK: - 二次应用幂等

    func testSecondApplyIsIdempotentAndByteStable() throws {
        let url = try writeFixture("model = \"gpt-5\"\r\n[real]\r\n")
        XCTAssertEqual(apply(auto: false, to: url), .inserted)
        let after = try bytes(of: url)
        XCTAssertEqual(apply(auto: false, to: url), .alreadyDesired)
        XCTAssertEqual(try bytes(of: url), after, "第二次应用不得产生任何字节变化")

        XCTAssertEqual(apply(auto: true, to: url), .replaced)
        let afterSwitch = try bytes(of: url)
        XCTAssertEqual(apply(auto: true, to: url), .alreadyDesired)
        XCTAssertEqual(try bytes(of: url), afterSwitch)
    }

    // MARK: - fail-safe 边界

    func testMissingConfigIsReportedAndNotCreated() {
        let url = root.appendingPathComponent("absent.toml")
        XCTAssertEqual(apply(auto: false, to: url), .missingConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "缺文件不得被创建")
    }

    func testNonUTF8ConfigIsLeftUntouched() throws {
        let url = try writeFixture(bytes: [0x61, 0x70, 0x70, 0xFF, 0xFE, 0x0A])
        let before = try bytes(of: url)
        XCTAssertEqual(apply(auto: true, to: url), .unreadableConfig)
        XCTAssertEqual(try bytes(of: url), before, "非 UTF-8 必须原样保留")
    }

    func testWriteFailureIsTypedAndLeavesOriginalContent() throws {
        try XCTSkipIf(geteuid() == 0, "root 会绕过只读目录")
        let url = try writeFixture("approval_policy = \"never\"\nmodel = \"gpt-5\"\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        }
        XCTAssertEqual(apply(auto: false, to: url), .writeFailed)
        XCTAssertEqual(try text(of: url), "approval_policy = \"never\"\nmodel = \"gpt-5\"\n")
    }

    // MARK: - 生产路径不得被测试触碰

    func testProductionConfigURLPointsAtRealHomeCodexConfig() {
        let url = CodexConfigLeverSync.productionConfigURL
        XCTAssertTrue(url.path.hasSuffix("/.codex/config.toml"))
        XCTAssertFalse(url.path.hasPrefix(root.path), "生产路径不得落在测试临时目录")
    }
}
