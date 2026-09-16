import XCTest

/// 以程序方式构造 raw string 字面量源码，避免手写 `\#(` 被 Swift 自身的定界符规则吞掉：
/// `\#(` 写在 `#"…"#` 内部会静默失义（C5IR8 行数据缺陷的成因）。
/// `markerHashes` 是插值标记的 hash 数，只有与 `hashes` 精确相等时该调用才可见。
private func rawSrc(hashes: Int, markerHashes: Int, body: String) -> String {
    let fence = String(repeating: "#", count: hashes)
    let marker = "\\" + String(repeating: "#", count: markerHashes) + "("
    return "let s = " + fence + "\"" + marker + body + fence + "\"" + fence
}

/// C5IR8：`SwiftSourceBoundaryAudit` 深模块的永久回归。
///
/// 结构：
/// 1. `protectedInterpolationRows` —— 机器生成 **8 string form × 2 protected symbol × 3 prefix = 48**；
/// 2. 一字符翻转矩阵（hash ±1 / ordinary 去反斜杠）必须翻转为 benign；
/// 3. 对称 benign 矩阵（符号文本出现在纯字符串 / line comment / nested block comment）；
/// 4. 状态转移矩阵（EOF、malformed、hash 前缀、声明 trivia、参数 trivia、越界、UTF-8 …）；
/// 5. 旧回归迁移账本（`LegacyRegressionID` 集合等式 + 行数不缩水）。
///
/// 说明：fixture 统一称为 **auditable source**（词法可扫描，但不要求 type-check）；
/// command 轴的 `sendDirectCommandFrame(0x96)` 是**字面量调用**，因此它的可观测是
/// `Report.calls` 里出现 0x96（integration gate 才把「产品树必须只有 0x00/0x94」判为违规）。
final class SwiftSourceBoundaryAuditTests: XCTestCase {

    // MARK: - 基础

    private func runAudit(_ text: String, path: String = "fixture.swift") -> SwiftSourceBoundaryAudit.Report {
        SwiftSourceBoundaryAudit.audit([.init(path: path, text: text)])
    }

    private func runAudit(bytes: [UInt8], path: String = "fixture.swift") -> SwiftSourceBoundaryAudit.Report {
        SwiftSourceBoundaryAudit.audit([.init(path: path, bytes: bytes)])
    }

    private enum ViolationKind: Equatable {
        case invalidUTF8
        case unterminatedString(String)
        case unterminatedBlockComment(Int)
        case unterminatedInterpolation(Int)
        case referenceWithoutCall
        case nonLiteral(String)
        case opcodeOutOfRange(String)
        case authority
    }

    private func kind(of violation: SwiftSourceBoundaryAudit.Violation) -> ViolationKind {
        switch violation {
        case let .malformedSource(_, reason):
            switch reason {
            case .invalidUTF8: return .invalidUTF8
            case let .unterminatedString(kind): return .unterminatedString(kind)
            case let .unterminatedBlockComment(depth): return .unterminatedBlockComment(depth)
            case let .unterminatedInterpolation(depth): return .unterminatedInterpolation(depth)
            }
        case .directCommandReferenceWithoutCall:
            return .referenceWithoutCall
        case let .nonLiteralDirectCommand(_, rendered):
            return .nonLiteral(rendered)
        case let .directCommandOpcodeOutOfRange(_, spelling):
            return .opcodeOutOfRange(spelling)
        case .authorityReadbackReference:
            return .authority
        }
    }

    private enum Expectation: Equatable {
        case clean
        /// `.complete`，opcode multiset 精确等于给定值，且 violations 为空。
        case calls([UInt8])
        /// `.complete`，calls 为空，violation kinds 精确等于给定序列。
        case violations([ViolationKind])
        /// 整个 audit `.malformed`，且只有一条给定 reason 的 violation。
        case malformed(ViolationKind)
    }

    private func assertExpectation(
        _ expectation: Expectation,
        report: SwiftSourceBoundaryAudit.Report,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch expectation {
        case .clean:
            guard case let .complete(complete) = report else {
                return XCTFail("\(label)：期望 complete，实得 malformed \(report)", file: file, line: line)
            }
            XCTAssertTrue(complete.calls.isEmpty, "\(label)：期望零 calls，实得 \(complete.calls)", file: file, line: line)
            XCTAssertTrue(complete.violations.isEmpty, "\(label)：期望零 violations，实得 \(complete.violations)", file: file, line: line)
        case let .calls(opcodes):
            guard case let .complete(complete) = report else {
                return XCTFail("\(label)：期望 complete，实得 malformed \(report)", file: file, line: line)
            }
            XCTAssertEqual(complete.opcodeMultiset, opcodes, "\(label)：calls 不符", file: file, line: line)
            XCTAssertTrue(complete.violations.isEmpty, "\(label)：期望零 violations，实得 \(complete.violations)", file: file, line: line)
        case let .violations(kinds):
            guard case let .complete(complete) = report else {
                return XCTFail("\(label)：期望 complete，实得 malformed \(report)", file: file, line: line)
            }
            XCTAssertTrue(complete.calls.isEmpty, "\(label)：期望零 calls，实得 \(complete.calls)", file: file, line: line)
            XCTAssertEqual(complete.violations.map(kind(of:)), kinds, "\(label)：violations 不符", file: file, line: line)
        case let .malformed(expected):
            guard case let .malformed(violations) = report else {
                return XCTFail("\(label)：期望整个 audit malformed，实得 \(report)", file: file, line: line)
            }
            XCTAssertEqual(violations.count, 1, "\(label)：malformed 必须恰一条 violation，实得 \(violations)", file: file, line: line)
            XCTAssertEqual(violations.first.map(kind(of:)), expected, "\(label)：malformed reason 不符", file: file, line: line)
        }
    }

    // MARK: - 机器生成：48 protected rows

    struct StringForm {
        let name: String
        let open: String
        let close: String
        let interpolationPrefix: String
        let multiline: Bool
    }

    static let forms: [StringForm] = [
        .init(name: "ordinary-single", open: "\"", close: "\"", interpolationPrefix: "\\(", multiline: false),
        .init(name: "ordinary-multiline", open: "\"\"\"", close: "\"\"\"", interpolationPrefix: "\\(", multiline: true),
        .init(name: "raw1-single", open: "#\"", close: "\"#", interpolationPrefix: "\\#(", multiline: false),
        .init(name: "raw1-multiline", open: "#\"\"\"", close: "\"\"\"#", interpolationPrefix: "\\#(", multiline: true),
        .init(name: "raw2-single", open: "##\"", close: "\"##", interpolationPrefix: "\\##(", multiline: false),
        .init(name: "raw2-multiline", open: "##\"\"\"", close: "\"\"\"##", interpolationPrefix: "\\##(", multiline: true),
        .init(name: "raw3-single", open: "###\"", close: "\"###", interpolationPrefix: "\\###(", multiline: false),
        .init(name: "raw3-multiline", open: "###\"\"\"", close: "\"\"\"###", interpolationPrefix: "\\###(", multiline: true),
    ]

    static let protectedSymbols = [
        "command": "sendDirectCommandFrame(0x96)",
        "authority": "store.applyAuthoritativeFieldReadback(deviceID: d, pageID: p, fieldID: f, value: v, version: ver)",
    ]

    static let prefixExpressions = [
        "nested-call": "helper() + ",
        "tuple": "(helper(), 0).1 + ",
        "closure": "{ helper() }() + ",
    ]

    /// 插值表达式自己的闭合括号——漏掉它会让整段 fixture 变成「未闭合字符串」，
    /// 从而 48 行全部假绿成 malformed（C5IR8 生成器自校验要挡住这一类空转）。
    static let interpolationClose = ")"

    struct ProtectedRow {
        let id: String
        let source: String
        let symbolKey: String
    }

    static let protectedInterpolationRows: [ProtectedRow] = {
        var rows: [ProtectedRow] = []
        for form in forms {
            for (symbolKey, symbol) in protectedSymbols.sorted(by: { $0.key < $1.key }) {
                for (prefixKey, prefix) in prefixExpressions.sorted(by: { $0.key < $1.key }) {
                    let body = form.interpolationPrefix + prefix + symbol + interpolationClose
                    let inner = form.multiline ? "\n" + body + "\n" : body
                    rows.append(ProtectedRow(
                        id: "protected.\(form.name).\(symbolKey).\(prefixKey)",
                        source: "let s = " + form.open + inner + form.close,
                        symbolKey: symbolKey
                    ))
                }
            }
        }
        return rows
    }()

    func testProtectedInterpolationMatrixIsCompleteUniqueAndVisible() {
        let rows = Self.protectedInterpolationRows
        // 生成器自校验 1：唯一且数量精确 48 = 8 × 2 × 3。
        XCTAssertEqual(rows.count, 48, "protected 矩阵必须是 8 × 2 × 3 = 48")
        XCTAssertEqual(Set(rows.map(\.id)).count, 48, "protected row id 必须唯一")
        XCTAssertEqual(Set(rows.map(\.source)).count, 48, "protected source 必须唯一")
        XCTAssertEqual(Set(rows.map { $0.id.split(separator: ".")[1] }).count, 8, "8 种 string form 全覆盖")
        XCTAssertEqual(Set(rows.map(\.symbolKey)), ["command", "authority"], "2 种 protected symbol 全覆盖")

        for row in rows {
            let report = runAudit(row.source)
            // 生成器自校验 2：每行必须**恰一条**可观测结果（command → 恰一 calls；authority → 恰一 violation）。
            switch row.symbolKey {
            case "command":
                guard case let .complete(complete) = report else {
                    XCTFail("\(row.id)：期望 complete，实得 \(report)")
                    continue
                }
                XCTAssertEqual(complete.calls.count, 1, "\(row.id)：插值内 command 调用必须可见")
                XCTAssertEqual(complete.opcodeMultiset, [0x96], "\(row.id)：opcode 必须为 0x96")
                XCTAssertTrue(complete.violations.isEmpty, "\(row.id)：不应有 violations：\(complete.violations)")
            case "authority":
                guard case let .complete(complete) = report else {
                    XCTFail("\(row.id)：期望 complete，实得 \(report)")
                    continue
                }
                XCTAssertTrue(complete.calls.isEmpty, "\(row.id)：不应有 calls")
                XCTAssertEqual(
                    complete.violations.map(kind(of:)), [.authority],
                    "\(row.id)：插值内 authority 引用必须恰一条 violation"
                )
            default:
                XCTFail("\(row.id)：未知 symbol key")
            }
        }
    }

    // MARK: - 一字符翻转（protected → benign）

    struct FlipRow {
        let id: String
        let protectedSource: String
        let flippedSource: String
    }

    static let interpolationFlipRows: [FlipRow] = {
        var rows: [FlipRow] = []
        let symbol = "sendDirectCommandFrame(0x96)"
        for form in forms {
            let body = form.interpolationPrefix + symbol + interpolationClose
            let protectedSource = "let s = " + form.open + (form.multiline ? "\n" + body + "\n" : body) + form.close
            // 一字符变异：ordinary 去掉反斜杠；raw 的 hash 数 ±1（仍是词法合法前缀，但不再精确匹配）。
            let hashCount = form.interpolationPrefix.filter { $0 == "#" }.count
            let mutatedPrefix: String
            if hashCount == 0 {
                mutatedPrefix = "("
            } else if hashCount == 1 {
                mutatedPrefix = "\\("
            } else {
                mutatedPrefix = "\\" + String(repeating: "#", count: hashCount - 1) + "("
            }
            let flippedBody = mutatedPrefix + symbol + interpolationClose
            let flippedSource = "let s = " + form.open + (form.multiline ? "\n" + flippedBody + "\n" : flippedBody) + form.close
            rows.append(FlipRow(
                id: "flip.\(form.name)",
                protectedSource: protectedSource,
                flippedSource: flippedSource
            ))
        }
        return rows
    }()

    func testOneCharacterInterpolationFlipTurnsProtectedIntoBenign() {
        let rows = Self.interpolationFlipRows
        XCTAssertEqual(rows.count, 8, "8 种形态各一行一字符翻转")
        XCTAssertEqual(Set(rows.map(\.flippedSource)).count, 8, "翻转后的 source 必须唯一")
        for row in rows {
            // 前提：protected 版本可见（否则翻转没有意义 —— 生成器空转变异）。
            assertExpectation(.calls([0x96]), report: runAudit(row.protectedSource), "\(row.id).protected")
            // 变异后：前缀不再匹配 delimiter hash count ⇒ 符号成为纯文本 ⇒ 完全 clean。
            assertExpectation(.clean, report: runAudit(row.flippedSource), "\(row.id).flipped")
        }
    }

    // MARK: - 对称 benign 矩阵

    struct BenignRow {
        let id: String
        let source: String
    }

    static let benignRows: [BenignRow] = {
        var rows: [BenignRow] = []
        for form in forms {
            for (symbolKey, symbol) in protectedSymbols.sorted(by: { $0.key < $1.key }) {
                let body = symbol // 没有插值前缀：整段是字符串纯文本
                rows.append(BenignRow(
                    id: "benign.string.\(form.name).\(symbolKey)",
                    source: "let s = " + form.open + (form.multiline ? "\n" + body + "\n" : body) + form.close
                ))
            }
        }
        for (symbolKey, symbol) in protectedSymbols.sorted(by: { $0.key < $1.key }) {
            rows.append(BenignRow(id: "benign.line-comment.\(symbolKey)", source: "// " + symbol))
            rows.append(BenignRow(id: "benign.block-comment.\(symbolKey)", source: "/* outer /* " + symbol + " */ */"))
        }
        return rows
    }()

    func testBenignSymmetryMatrixIsCleanAndUnique() {
        let rows = Self.benignRows
        XCTAssertEqual(rows.count, 20, "8 × 2 纯文本 + 2 × 2 注释 = 20")
        XCTAssertEqual(Set(rows.map(\.id)).count, 20, "benign row id 必须唯一")
        XCTAssertEqual(Set(rows.map(\.source)).count, 20, "benign source 必须唯一")
        for row in rows {
            assertExpectation(.clean, report: runAudit(row.source), row.id)
        }
    }

    // MARK: - 状态转移矩阵

    private struct StateCase {
        let id: String
        let source: String
        let expectation: Expectation
    }

    private static let stateCases: [StateCase] = [
        // EOF / line comment
        .init(id: "eof.root-line-comment",
              source: "let a = 1 // trailing comment",
              expectation: .clean),
        .init(id: "eof.interpolation-line-comment",
              source: #"let s = "\(foo // EOF"#,
              expectation: .malformed(.unterminatedInterpolation(1))),
        // interpolation 嵌套
        .init(id: "lexical.interpolation.nested-string",
              source: #"let s = "\(f(/*c*/ "x\(sendDirectCommandFrame(0x96))"))""#,
              expectation: .calls([0x96])),
        .init(id: "lexical.interpolation.nested-array",
              source: #"let s = "\([helper()].count + sendDirectCommandFrame(0x96))""#,
              expectation: .calls([0x96])),
        .init(id: "lexical.interpolation.depth",
              source: #"let s = "\(helper() + sendDirectCommandFrame(0x96))""#,
              expectation: .calls([0x96])),
        // raw hash 前缀：精确才进 interpolation
        .init(id: "raw.hash1.lower-prefix-text",
              source: rawSrc(hashes: 1, markerHashes: 0, body: "sendDirectCommandFrame(0x96))"),
              expectation: .clean),
        .init(id: "raw.hash1.higher-prefix-text",
              source: rawSrc(hashes: 1, markerHashes: 2, body: "sendDirectCommandFrame(0x96))"),
              expectation: .clean),
        .init(id: "raw.hash2.lower-prefix-text",
              source: rawSrc(hashes: 2, markerHashes: 1, body: "sendDirectCommandFrame(0x96))"),
              expectation: .clean),
        .init(id: "raw.hash2.higher-prefix-text",
              source: rawSrc(hashes: 2, markerHashes: 3, body: "sendDirectCommandFrame(0x96))"),
              expectation: .clean),
        .init(id: "raw.hash2.exact-prefix-visible",
              source: rawSrc(hashes: 2, markerHashes: 2, body: "sendDirectCommandFrame(0x96))"),
              expectation: .calls([0x96])),
        .init(id: "raw.hash3.lower-prefix-text",
              source: rawSrc(hashes: 3, markerHashes: 2, body: "sendDirectCommandFrame(0x96))"),
              expectation: .clean),
        .init(id: "raw.hash3.higher-prefix-text",
              source: rawSrc(hashes: 3, markerHashes: 4, body: "sendDirectCommandFrame(0x96))"),
              expectation: .clean),
        .init(id: "raw.hash3.exact-prefix-visible",
              source: rawSrc(hashes: 3, markerHashes: 3, body: "sendDirectCommandFrame(0x96))"),
              expectation: .calls([0x96])),
        // raw multiline 终止符与「不吞后续代码」
        .init(id: "raw.hash1.multiline.inner-hash-quote",
              source: "let s = #\"\"\"\n\"#\n\"\"\"#\nlet a = 1",
              expectation: .clean),
        .init(id: "raw.hash1.multiline.following-code",
              source: "let s = #\"\"\"\n\"#\n\"\"\"#\nsendDirectCommandFrame(0x96)",
              expectation: .calls([0x96])),
        // 注释深度
        .init(id: "lexical.block-comment-depth.closed",
              source: "/* outer /* inner */ */\nlet a = 1",
              expectation: .clean),
        .init(id: "lexical.block-comment-depth.unterminated-1",
              source: "let a = 1 /* x",
              expectation: .malformed(.unterminatedBlockComment(1))),
        .init(id: "lexical.block-comment-depth.unterminated-2",
              source: "let a = 1 /* /* x",
              expectation: .malformed(.unterminatedBlockComment(2))),
        .init(id: "lexical.block-comment-depth.nested-close-leaves-outer-1",
              source: "let a = 1 /* /* x */",
              expectation: .malformed(.unterminatedBlockComment(1))),
        // 字符串终止
        .init(id: "lexical.string-termination.ordinary",
              source: "let s = \"abc",
              expectation: .malformed(.unterminatedString("ordinary"))),
        .init(id: "lexical.string-termination.multiline",
              source: "let s = \"\"\"\nabc",
              expectation: .malformed(.unterminatedString("ordinary-multiline"))),
        .init(id: "lexical.string-termination.raw",
              source: #"let s = #"abc"#,
              expectation: .malformed(.unterminatedString("raw(hashes: 1, multiline: false)"))),
        .init(id: "malformed.interpolation",
              source: #"let s = "\(foo("#,
              expectation: .malformed(.unterminatedInterpolation(2))),
        // direct command 参数
        .init(id: "direct.literal",
              source: "sendDirectCommandFrame(0x94, payload: [0x01])",
              expectation: .calls([0x94])),
        .init(id: "direct.literal-newline",
              source: "sendDirectCommandFrame(\n    0x97\n)",
              expectation: .calls([0x97])),
        .init(id: "direct.variable",
              source: "let opcode: UInt8 = 0x96\nsendDirectCommandFrame(opcode)",
              expectation: .violations([.nonLiteral("opcode")])),
        .init(id: "direct.binary",
              source: "sendDirectCommandFrame(0x00 | 0x96)",
              expectation: .violations([.nonLiteral("0x00 | 0x96")])),
        .init(id: "direct.parenthesized",
              source: "sendDirectCommandFrame((0x00))",
              expectation: .violations([.nonLiteral("(0x00)")])),
        .init(id: "direct.function-result",
              source: "sendDirectCommandFrame(Self.opcode())",
              expectation: .violations([.nonLiteral("Self.opcode()")])),
        .init(id: "direct.array",
              source: "sendDirectCommandFrame([0x96])",
              expectation: .violations([.nonLiteral("[0x96]")])),
        .init(id: "direct.dictionary",
              source: "sendDirectCommandFrame([0x01: 0x96])",
              expectation: .violations([.nonLiteral("[0x01: 0x96]")])),
        .init(id: "direct.closure",
              source: "sendDirectCommandFrame({ 0x96 }())",
              expectation: .violations([.nonLiteral("{ 0x96 }()")])),
        .init(id: "direct.subscript",
              source: "sendDirectCommandFrame(opcodes[0])",
              expectation: .violations([.nonLiteral("opcodes[0]")])),
        .init(id: "direct.unterminated-paren",
              source: "sendDirectCommandFrame(make(0x96)",
              expectation: .violations([.nonLiteral("<unterminated>")])),
        .init(id: "direct.unterminated-bracket",
              source: "sendDirectCommandFrame([0x96)",
              expectation: .violations([.nonLiteral("<unterminated>")])),
        .init(id: "direct.unterminated-brace",
              source: "sendDirectCommandFrame({ 0x96)",
              expectation: .violations([.nonLiteral("<unterminated>")])),
        .init(id: "direct.mismatched-top-level-closer",
              source: "sendDirectCommandFrame(0x00], 0x96)",
              expectation: .violations([.nonLiteral("<unterminated>")])),
        .init(id: "direct.reference-without-call",
              source: "let f = sendDirectCommandFrame",
              expectation: .violations([.referenceWithoutCall])),
        .init(id: "direct.empty-argument",
              source: "sendDirectCommandFrame()",
              expectation: .violations([.nonLiteral("<empty>")])),
        .init(id: "direct.whitespace-argument",
              source: "sendDirectCommandFrame( /*c*/ )",
              expectation: .violations([.nonLiteral("<empty>")])),
        .init(id: "direct.argument-comment-trivia-leading",
              source: "sendDirectCommandFrame(/*c*/ 0x00)",
              expectation: .calls([0x00])),
        .init(id: "direct.argument-comment-trivia-trailing",
              source: "sendDirectCommandFrame(0x00 /*c*/)",
              expectation: .calls([0x00])),
        .init(id: "direct.argument-comment-line-trivia",
              source: "sendDirectCommandFrame(0x00 // c\n)",
              expectation: .calls([0x00])),
        .init(id: "direct.opcode-out-of-range-small",
              source: "sendDirectCommandFrame(0x100)",
              expectation: .violations([.opcodeOutOfRange("0x100")])),
        .init(id: "direct.opcode-out-of-range-huge",
              source: "sendDirectCommandFrame(0x10000000000000000)",
              expectation: .violations([.opcodeOutOfRange("0x10000000000000000")])),
        // 声明排除（结构化，含 trivia）
        .init(id: "declaration.single-space",
              source: "func sendDirectCommandFrame(_ opcode: UInt8) {}\nsendDirectCommandFrame(0x00)",
              expectation: .calls([0x00])),
        .init(id: "declaration.double-space",
              source: "func  sendDirectCommandFrame(_ opcode: UInt8) {}\nsendDirectCommandFrame(0x00)",
              expectation: .calls([0x00])),
        .init(id: "declaration.tab",
              source: "func\tsendDirectCommandFrame(_ opcode: UInt8) {}\nsendDirectCommandFrame(0x00)",
              expectation: .calls([0x00])),
        .init(id: "declaration.newline",
              source: "func\n    sendDirectCommandFrame(_ opcode: UInt8) {}\nsendDirectCommandFrame(0x00)",
              expectation: .calls([0x00])),
        .init(id: "declaration.comment-trivia",
              source: "func /*c*/ sendDirectCommandFrame(_ opcode: UInt8) {}\nsendDirectCommandFrame(0x00)",
              expectation: .calls([0x00])),
        .init(id: "declaration.default-args",
              source: "func sendDirectCommandFrame(_ opcode: UInt8, payload: [UInt8] = []) {",
              expectation: .clean),
        // authority
        .init(id: "authority.direct",
              source: "store.applyAuthoritativeFieldReadback(deviceID: d, pageID: p, fieldID: f, value: v, version: ver)",
              expectation: .violations([.authority])),
        .init(id: "authority.alias",
              source: "let f = store.applyAuthoritativeFieldReadback",
              expectation: .violations([.authority])),
        .init(id: "authority.declaration-excluded",
              source: "func applyAuthoritativeFieldReadback(a: Int) {}\nstore.applyAuthoritativeFieldReadback(a: 1)",
              expectation: .violations([.authority])),
        .init(id: "authority.similar-name-not-counted",
              source: "store.applyAuthoritativeFieldReadbackExtra(a: 1)",
              expectation: .clean),
        .init(id: "authority.suffixed-name-not-counted",
              source: "let applyAuthoritativeFieldReadbackV2 = 1",
              expectation: .clean),
    ]

    func testStateTransitionMatrix() {
        XCTAssertEqual(Self.stateCases.count, Set(Self.stateCases.map(\.id)).count, "state case id 必须唯一")
        for stateCase in Self.stateCases {
            assertExpectation(stateCase.expectation, report: runAudit(stateCase.source), stateCase.id)
        }
    }

    /// 非 UTF-8 是**整个 audit** 的 typed malformed（单独用例，因为需要 bytes 入口）。
    func testInvalidUTF8MakesWholeAuditMalformed() {
        let report = runAudit(bytes: [0x6C, 0x65, 0x74, 0xFF, 0xFE])
        assertExpectation(.malformed(.invalidUTF8), report: report, "malformed.invalid-utf8")
    }

    /// 多文件：任一文件 malformed ⇒ 整个 audit `.malformed`，不暴露缩短后的 inventory。
    func testAnyMalformedFileSuppressesWholeInventory() {
        let sources = [
            SwiftSourceBoundaryAudit.SourceFile(path: "a-clean.swift", text: "sendDirectCommandFrame(0x00)"),
            SwiftSourceBoundaryAudit.SourceFile(path: "b-broken.swift", text: "let s = \"abc"),
        ]
        let report = SwiftSourceBoundaryAudit.audit(sources)
        guard case let .malformed(violations) = report else {
            return XCTFail("任一 malformed 必须让整个 audit malformed，实得 \(report)")
        }
        XCTAssertFalse(report.isClean)
        XCTAssertEqual(violations.map(kind(of:)), [.unterminatedString("ordinary")])
    }

    /// 排序稳定性：多文件、乱序输入，calls 必须按 path/offset 排序。
    func testCallsAreSortedByPathAndOffset() {
        let sources = [
            SwiftSourceBoundaryAudit.SourceFile(path: "z.swift", text: "sendDirectCommandFrame(0x94)"),
            SwiftSourceBoundaryAudit.SourceFile(path: "a.swift", text: "sendDirectCommandFrame(0x00)"),
        ]
        let report = SwiftSourceBoundaryAudit.audit(sources)
        guard case let .complete(complete) = report else { return XCTFail("期望 complete") }
        XCTAssertEqual(complete.calls.map(\.location.path), ["a.swift", "z.swift"])
        XCTAssertEqual(complete.calls.map(\.opcode), [0x00, 0x94])
        XCTAssertEqual(complete.calls.map(\.location.line), [1, 1])
        XCTAssertEqual(complete.calls.map(\.location.column), [1, 1])
    }

    /// 行/列/offset 是 1-based 且可定位（红环输入也在此冻结位置）。
    func testLocationsAreOneBasedAndTraceable() {
        let report = runAudit("let a = 1\nsendDirectCommandFrame(0x00)")
        guard case let .complete(complete) = report else { return XCTFail("期望 complete") }
        XCTAssertEqual(complete.calls.count, 1)
        XCTAssertEqual(complete.calls.first?.location.line, 2)
        XCTAssertEqual(complete.calls.first?.location.column, 1)
        XCTAssertEqual(complete.calls.first?.location.utf16Offset, 10)

        let malformedReport = runAudit(#"let s = "\(foo // EOF"#)
        guard case let .malformed(violations) = malformedReport else { return XCTFail("期望 malformed") }
        XCTAssertEqual(violations.first?.location.line, 1)
        XCTAssertEqual(violations.first?.location.utf16Offset, 21)
    }

    // MARK: - 旧回归迁移账本

    enum LegacyRegressionID: String, CaseIterable {
        case directLiteral = "direct.literal"
        case directLiteralNewline = "direct.literal-newline"
        case directVariable = "direct.variable"
        case directBinary = "direct.binary"
        case directParenthesized = "direct.parenthesized"
        case directFunctionResult = "direct.function-result"
        case directArray = "direct.array"
        case directDictionary = "direct.dictionary"
        case directClosure = "direct.closure"
        case directSubscript = "direct.subscript"
        case directUnterminatedParen = "direct.unterminated-paren"
        case directUnterminatedBracket = "direct.unterminated-bracket"
        case directUnterminatedBrace = "direct.unterminated-brace"
        case directReferenceWithoutCall = "direct.reference-without-call"
        case directEmptyArgument = "direct.empty-argument"
        case directWhitespaceArgument = "direct.whitespace-argument"
        case directArgumentCommentLeading = "direct.argument-comment-trivia-leading"
        case directArgumentCommentTrailing = "direct.argument-comment-trivia-trailing"
        case directArgumentCommentLine = "direct.argument-comment-line-trivia"
        case directOpcodeOutOfRangeSmall = "direct.opcode-out-of-range-small"
        case directOpcodeOutOfRangeHuge = "direct.opcode-out-of-range-huge"
        case declarationSingleSpace = "declaration.single-space"
        case declarationDoubleSpace = "declaration.double-space"
        case declarationTab = "declaration.tab"
        case declarationNewline = "declaration.newline"
        case declarationCommentTrivia = "declaration.comment-trivia"
        case declarationDefaultArgs = "declaration.default-args"
        case authorityDirect = "authority.direct"
        case authorityAlias = "authority.alias"
        case authorityDeclarationExcluded = "authority.declaration-excluded"
        case authoritySimilarName = "authority.similar-name-not-counted"
        case authoritySuffixedName = "authority.suffixed-name-not-counted"
        case lexicalStringOrdinary = "lexical.string-termination.ordinary"
        case lexicalStringMultiline = "lexical.string-termination.multiline"
        case lexicalStringRaw = "lexical.string-termination.raw"
        case lexicalBlockClosed = "lexical.block-comment-depth.closed"
        case lexicalBlockUnterminated1 = "lexical.block-comment-depth.unterminated-1"
        case lexicalBlockUnterminated2 = "lexical.block-comment-depth.unterminated-2"
        case lexicalBlockNestedCloseLeavesOuter = "lexical.block-comment-depth.nested-close-leaves-outer-1"
        case lexicalInterpolationDepth = "lexical.interpolation.depth"
        case lexicalInterpolationNestedString = "lexical.interpolation.nested-string"
        case lexicalInterpolationNestedArray = "lexical.interpolation.nested-array"
        case rawHash1MultilineInnerHashQuote = "raw.hash1.multiline.inner-hash-quote"
        case rawHash1MultilineFollowingCode = "raw.hash1.multiline.following-code"
        case rawHash1LowerPrefixText = "raw.hash1.lower-prefix-text"
        case rawHash1HigherPrefixText = "raw.hash1.higher-prefix-text"
        case rawHash2LowerPrefixText = "raw.hash2.lower-prefix-text"
        case rawHash2ExactPrefixVisible = "raw.hash2.exact-prefix-visible"
        case rawHash3LowerPrefixText = "raw.hash3.lower-prefix-text"
        case rawHash3ExactPrefixVisible = "raw.hash3.exact-prefix-visible"
        case malformedInterpolation = "malformed.interpolation"
        case malformedInvalidUTF8 = "malformed.invalid-utf8"
        case eofRootLineComment = "eof.root-line-comment"
        case eofInterpolationLineComment = "eof.interpolation-line-comment"
    }

    /// 显式迁移账本：不从 `allCases` 自我派生，以便新增/删除 legacy ID 时必须同步裁决映射。
    static let migratedLegacyIDs: [LegacyRegressionID] = [
        .directLiteral,
        .directLiteralNewline,
        .directVariable,
        .directBinary,
        .directParenthesized,
        .directFunctionResult,
        .directArray,
        .directDictionary,
        .directClosure,
        .directSubscript,
        .directUnterminatedParen,
        .directUnterminatedBracket,
        .directUnterminatedBrace,
        .directReferenceWithoutCall,
        .directEmptyArgument,
        .directWhitespaceArgument,
        .directArgumentCommentLeading,
        .directArgumentCommentTrailing,
        .directArgumentCommentLine,
        .directOpcodeOutOfRangeSmall,
        .directOpcodeOutOfRangeHuge,
        .declarationSingleSpace,
        .declarationDoubleSpace,
        .declarationTab,
        .declarationNewline,
        .declarationCommentTrivia,
        .declarationDefaultArgs,
        .authorityDirect,
        .authorityAlias,
        .authorityDeclarationExcluded,
        .authoritySimilarName,
        .authoritySuffixedName,
        .lexicalStringOrdinary,
        .lexicalStringMultiline,
        .lexicalStringRaw,
        .lexicalBlockClosed,
        .lexicalBlockUnterminated1,
        .lexicalBlockUnterminated2,
        .lexicalBlockNestedCloseLeavesOuter,
        .lexicalInterpolationDepth,
        .lexicalInterpolationNestedString,
        .lexicalInterpolationNestedArray,
        .rawHash1MultilineInnerHashQuote,
        .rawHash1MultilineFollowingCode,
        .rawHash1LowerPrefixText,
        .rawHash1HigherPrefixText,
        .rawHash2LowerPrefixText,
        .rawHash2ExactPrefixVisible,
        .rawHash3LowerPrefixText,
        .rawHash3ExactPrefixVisible,
        .malformedInterpolation,
        .malformedInvalidUTF8,
        .eofRootLineComment,
        .eofInterpolationLineComment,
    ]

    /// 旧树被替换删除的永久 row 数（C5IR7/C5IR8 工作树实测：lexer 31 + parser/declaration 26 + authority 9 + cross 12）。
    static let legacyPermanentRowCount = 78

    func testLegacyRegressionLedgerIsMigratedAndDoesNotShrink() {
        let stateIDs = Set(Self.stateCases.map(\.id))
        let extraIDs: Set<String> = ["malformed.invalid-utf8", "malformed.interpolation"]
        let migrated = stateIDs.union(extraIDs)

        // 机械门 1：显式迁移账本与冻结 enum 必须双向集合相等，且不得用重复项凑数。
        let expectedLegacyIDs = Set(LegacyRegressionID.allCases)
        let explicitMigratedIDs = Set(Self.migratedLegacyIDs)
        XCTAssertEqual(Self.migratedLegacyIDs.count, explicitMigratedIDs.count, "迁移账本不得重复")
        XCTAssertEqual(explicitMigratedIDs, expectedLegacyIDs, "显式迁移账本必须与 LegacyRegressionID 双向相等")

        let missingImplementations = explicitMigratedIDs
            .map(\.rawValue)
            .filter { !migrated.contains($0) }
        XCTAssertTrue(missingImplementations.isEmpty, "旧回归未迁入真实用例：\(missingImplementations)")

        // 机械门 2：新模块回归总数不小于被删旧永久 rows。
        let newRowCount = Self.protectedInterpolationRows.count
            + Self.interpolationFlipRows.count
            + Self.benignRows.count
            + Self.stateCases.count
        XCTAssertGreaterThanOrEqual(
            newRowCount, Self.legacyPermanentRowCount,
            "新 rows=\(newRowCount) 必须不小于旧永久 rows=\(Self.legacyPermanentRowCount)"
        )
    }
}
