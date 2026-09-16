import Foundation

/// C5IR8：Swift 源码边界审计深模块（tests-only，不随产品发布）。
///
/// 唯一对外 interface：`SwiftSourceBoundaryAudit.audit(sources:) -> Report`。
/// 调用方与测试**不得**触碰 tokenizer / mode stack / declaration 识别 / 参数解析——
/// 这些全部是本文件的 implementation。
///
/// 设计要点（对应 `docs/collab/reports/C5IR8-SWIFT-SOURCE-BOUNDARY-AUDIT-DESIGN.md`）：
/// - 一次 tokenization：注释与字符串**纯文本**不产生 token，interpolation expression 递归产生正常 token；
///   声明识别、调用识别、参数闭合全部消费同一 token 流，不再「剥字符串 + regex」。
/// - interpolation 携带 `parenDepth`，只有最外层配对 `)` 归零才回到 string。
/// - EOF 先弹出尾部 line comment，再要求 mode stack **精确**为 `[code]`；否则 typed `malformedSource`。
/// - 任一文件非 UTF-8 或词法未闭合 ⇒ **整个** audit 返回 `.malformed`，不暴露 calls/multiset。
struct SwiftSourceBoundaryAudit {
    // MARK: - 对外类型

    struct SourceFile: Equatable {
        let path: String
        let bytes: [UInt8]

        init(path: String, bytes: [UInt8]) {
            self.path = path
            self.bytes = bytes
        }

        /// 测试便捷入口：按 UTF-8 存字节（非 UTF-8 由 audit 统一转成 typed malformed）。
        init(path: String, text: String) {
            self.init(path: path, bytes: Array(text.utf8))
        }
    }

    /// 1-based line / 1-based UTF-16 column，外加 UTF-16 offset（排序与切片用）。
    struct SourceLocation: Equatable, Comparable {
        let path: String
        let line: Int
        let column: Int
        let utf16Offset: Int

        static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.utf16Offset < rhs.utf16Offset
        }
    }

    /// 唯一真实存在的 direct command callsite（字面量 opcode）。multiset 只是它的派生视图。
    struct DirectCommandCall: Equatable {
        let location: SourceLocation
        let opcode: UInt8
        let spelling: String
    }

    struct CompleteReport: Equatable {
        let calls: [DirectCommandCall]
        let violations: [Violation]

        var opcodeMultiset: [UInt8] { calls.map(\.opcode).sorted() }
        var isClean: Bool { violations.isEmpty }
    }

    enum Report: Equatable {
        case complete(CompleteReport)
        case malformed(violations: [Violation])

        var isClean: Bool {
            if case let .complete(report) = self { return report.isClean }
            return false
        }
    }

    enum LexicalFailure: Equatable {
        case invalidUTF8
        case unterminatedString(kind: String)
        case unterminatedBlockComment(depth: Int)
        case unterminatedInterpolation(depth: Int)
    }

    enum Violation: Equatable {
        case malformedSource(location: SourceLocation, reason: LexicalFailure)
        case directCommandReferenceWithoutCall(location: SourceLocation)
        case nonLiteralDirectCommand(location: SourceLocation, renderedArgument: String)
        case directCommandOpcodeOutOfRange(location: SourceLocation, spelling: String)
        case authorityReadbackReference(location: SourceLocation)

        var location: SourceLocation {
            switch self {
            case let .malformedSource(location, _),
                 let .directCommandReferenceWithoutCall(location),
                 let .nonLiteralDirectCommand(location, _),
                 let .directCommandOpcodeOutOfRange(location, _),
                 let .authorityReadbackReference(location):
                return location
            }
        }
    }

    static let directCommandSymbol = "sendDirectCommandFrame"
    static let authorityReadbackSymbol = "applyAuthoritativeFieldReadback"

    static func audit(_ sources: [SourceFile]) -> Report {
        var calls: [DirectCommandCall] = []
        var violations: [Violation] = []
        var sawMalformed = false

        for file in sources.sorted(by: { $0.path < $1.path }) {
            guard let text = String(bytes: file.bytes, encoding: .utf8) else {
                sawMalformed = true
                violations.append(.malformedSource(
                    location: SourceLocation(path: file.path, line: 1, column: 1, utf16Offset: 0),
                    reason: .invalidUTF8
                ))
                continue
            }
            let scanner = Scanner(path: file.path, units: Array(text.utf16))
            let outcome = scanner.scan()
            switch outcome {
            case let .failure(location, reason):
                sawMalformed = true
                violations.append(.malformedSource(location: location, reason: reason))
            case let .success(tokens):
                let fileResult = Policy(path: file.path, units: Array(text.utf16), tokens: tokens).evaluate()
                calls.append(contentsOf: fileResult.calls)
                violations.append(contentsOf: fileResult.violations)
            }
        }

        calls.sort { $0.location < $1.location }
        violations.sort { $0.location < $1.location }
        if sawMalformed {
            // 任一 malformed ⇒ 整个 audit 非 clean，且**不暴露** calls/multiset，
            // 因此不存在「跳过坏文件后 inventory 变短」的可表示状态。
            return .malformed(violations: violations)
        }
        return .complete(CompleteReport(calls: calls, violations: violations))
    }
}

// MARK: - 内部 token 模型

private enum TokenKind: Equatable {
    case identifier(String)
    case hexInteger(spelling: String, parsed: UInt64?)
    /// `( ) [ ] { } , . :`
    case punctuation(Character)
    case other(String)

    var spelling: String {
        switch self {
        case let .identifier(name): return name
        case let .hexInteger(spelling, _): return spelling
        case let .punctuation(character): return String(character)
        case let .other(text): return text
        }
    }

    func isPunctuation(_ character: Character) -> Bool {
        self == .punctuation(character)
    }
}

private struct Token: Equatable {
    let kind: TokenKind
    let location: SwiftSourceBoundaryAudit.SourceLocation
}

// MARK: - 字符串 delimiter

private struct StringDelimiter: Equatable {
    enum Kind: Equatable {
        case ordinary
        case raw(hashes: Int)
    }

    let kind: Kind
    let multiline: Bool

    var label: String {
        switch kind {
        case .ordinary: return multiline ? "ordinary-multiline" : "ordinary"
        case let .raw(hashes): return "raw(hashes: \(hashes), multiline: \(multiline))"
        }
    }

    var terminator: [UInt16] {
        let quotes = multiline ? "\"\"\"" : "\""
        switch kind {
        case .ordinary:
            return Array(quotes.utf16)
        case let .raw(hashes):
            return Array((quotes + String(repeating: "#", count: hashes)).utf16)
        }
    }

    var interpolationPrefix: [UInt16] {
        switch kind {
        case .ordinary:
            return Array("\\(".utf16)
        case let .raw(hashes):
            return Array(("\\" + String(repeating: "#", count: hashes) + "(").utf16)
        }
    }
}

// MARK: - scanner（一次 tokenization + mode stack）

private struct Scanner {
    enum Outcome {
        case success([Token])
        case failure(SwiftSourceBoundaryAudit.SourceLocation, SwiftSourceBoundaryAudit.LexicalFailure)
    }

    enum Mode {
        case code
        case lineComment
        case blockComment(depth: Int)
        case string(StringDelimiter)
        case interpolation(StringDelimiter, parenDepth: Int)
    }

    let path: String
    let units: [UInt16]

    private var index = 0
    private var line = 1
    private var column = 1
    private var tokens: [Token] = []
    private var stack: [Mode] = [.code]

    init(path: String, units: [UInt16]) {
        self.path = path
        self.units = units
    }

    private static let quote = UInt16(UInt8(ascii: "\""))
    private static let hash = UInt16(UInt8(ascii: "#"))
    private static let slash = UInt16(UInt8(ascii: "/"))
    private static let star = UInt16(UInt8(ascii: "*"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let newline = UInt16(UInt8(ascii: "\n"))
    private static let openParen = UInt16(UInt8(ascii: "("))
    private static let closeParen = UInt16(UInt8(ascii: ")"))
    private static let punctuations: Set<UInt16> = Set("()[]{},.:".utf16)

    func scan() -> Outcome {
        var scanner = self
        return scanner.run()
    }

    private mutating func run() -> Outcome {
        while index < units.count {
            switch stack[stack.count - 1] {
            case .code, .interpolation:
                scanCodeMode()
            case .lineComment:
                scanLineComment()
            case let .blockComment(depth):
                scanBlockComment(depth: depth)
            case let .string(delimiter):
                scanStringMode(delimiter)
            }
        }
        // EOF：先弹出尾部 line comment（行注释在 EOF 结束合法），再要求栈精确为 [code]。
        while let last = stack.last, case .lineComment = last {
            stack.removeLast()
        }
        if stack.count == 1, case .code = stack[0] {
            return .success(tokens)
        }
        let location = currentLocation()
        switch stack[stack.count - 1] {
        case .code:
            return .success(tokens)
        case let .string(delimiter):
            return .failure(location, .unterminatedString(kind: delimiter.label))
        case let .blockComment(depth):
            return .failure(location, .unterminatedBlockComment(depth: depth))
        case let .interpolation(_, depth):
            return .failure(location, .unterminatedInterpolation(depth: depth))
        case .lineComment:
            // 弹出后不可达；仅为穷尽性。
            return .success(tokens)
        }
    }

    // MARK: mode handlers

    private mutating func scanCodeMode() {
        let unit = units[index]
        if unit == Self.slash, peek(1) == Self.slash {
            stack.append(.lineComment)
            advance(2)
            return
        }
        if unit == Self.slash, peek(1) == Self.star {
            stack.append(.blockComment(depth: 1))
            advance(2)
            return
        }
        if unit == Self.hash, let start = rawStringStart() {
            let delimiter = StringDelimiter(
                kind: .raw(hashes: start.hashes),
                multiline: delimiterIsMultiline(atQuote: start.quoteIndex)
            )
            stack.append(.string(delimiter))
            advance(start.quoteIndex - index + (delimiter.multiline ? 3 : 1))
            return
        }
        if unit == Self.quote {
            let delimiter = StringDelimiter(kind: .ordinary, multiline: delimiterIsMultiline(atQuote: index))
            stack.append(.string(delimiter))
            advance(delimiter.multiline ? 3 : 1)
            return
        }
        if case let .interpolation(delimiter, depth) = stack[stack.count - 1] {
            if unit == Self.openParen {
                stack[stack.count - 1] = .interpolation(delimiter, parenDepth: depth + 1)
                emitPunctuation("(")
                return
            }
            if unit == Self.closeParen {
                stack[stack.count - 1] = depth == 1 ? .code : .interpolation(delimiter, parenDepth: depth - 1)
                if depth == 1 { stack.removeLast() }
                emitPunctuation(")")
                return
            }
        }
        if unit == UInt16(UInt8(ascii: "0")), peek(1) == UInt16(UInt8(ascii: "x")) || peek(1) == UInt16(UInt8(ascii: "X")) {
            emitHexInteger()
            return
        }
        if isIdentifierStart(unit) {
            emitIdentifier()
            return
        }
        if Self.punctuations.contains(unit), let character = character(from: unit) {
            emitPunctuation(character)
            return
        }
        if isWhitespace(unit) {
            advance(1)
            return
        }
        emitOther()
    }

    private mutating func scanLineComment() {
        if units[index] == Self.newline {
            stack.removeLast()
        }
        advance(1)
    }

    private mutating func scanBlockComment(depth: Int) {
        if units[index] == Self.slash, peek(1) == Self.star {
            stack[stack.count - 1] = .blockComment(depth: depth + 1)
            advance(2)
            return
        }
        if units[index] == Self.star, peek(1) == Self.slash {
            if depth == 1 {
                stack.removeLast()
            } else {
                stack[stack.count - 1] = .blockComment(depth: depth - 1)
            }
            advance(2)
            return
        }
        advance(1)
    }

    private mutating func scanStringMode(_ delimiter: StringDelimiter) {
        if matches(delimiter.interpolationPrefix) {
            // interpolation expression 是真实代码：进入 code 语义（递归产生 token）。
            stack.append(.interpolation(delimiter, parenDepth: 1))
            advance(delimiter.interpolationPrefix.count)
            return
        }
        if matches(delimiter.terminator) {
            stack.removeLast()
            advance(delimiter.terminator.count)
            return
        }
        if case .ordinary = delimiter.kind, units[index] == Self.backslash {
            advance(2)
            return
        }
        advance(1)
    }

    // MARK: emission

    private mutating func emitIdentifier() {
        let start = currentLocation()
        var value = String()
        while index < units.count, isIdentifierContinuation(units[index]) {
            value.append(character(from: units[index]) ?? "_")
            advance(1)
        }
        tokens.append(Token(kind: .identifier(value), location: start))
    }

    private mutating func emitHexInteger() {
        let start = currentLocation()
        var spelling = "0x"
        advance(2)
        while index < units.count, isHexDigit(units[index]) || units[index] == UInt16(UInt8(ascii: "_")) {
            spelling.append(character(from: units[index]) ?? "0")
            advance(1)
        }
        let digits = spelling.dropFirst(2).replacingOccurrences(of: "_", with: "")
        tokens.append(Token(
            kind: .hexInteger(spelling: spelling, parsed: digits.isEmpty ? nil : UInt64(digits, radix: 16)),
            location: start
        ))
    }

    private mutating func emitPunctuation(_ character: Character) {
        let start = currentLocation()
        advance(1)
        tokens.append(Token(kind: .punctuation(character), location: start))
    }

    private mutating func emitOther() {
        let start = currentLocation()
        var value = String()
        while index < units.count {
            let unit = units[index]
            if isWhitespace(unit) || isIdentifierStart(unit) || Self.punctuations.contains(unit) { break }
            if unit == Self.slash || unit == Self.quote || unit == Self.hash { break }
            value.append(character(from: unit) ?? "?")
            advance(1)
        }
        if value.isEmpty {
            value.append(character(from: units[index]) ?? "?")
            advance(1)
        }
        tokens.append(Token(kind: .other(value), location: start))
    }

    // MARK: helpers

    private func peek(_ offset: Int) -> UInt16? {
        let target = index + offset
        guard target >= 0, target < units.count else { return nil }
        return units[target]
    }

    private func matches(_ pattern: [UInt16]) -> Bool {
        guard !pattern.isEmpty, index + pattern.count <= units.count else { return false }
        for offset in 0 ..< pattern.count where units[index + offset] != pattern[offset] { return false }
        return true
    }

    private func rawStringStart() -> (hashes: Int, quoteIndex: Int)? {
        var cursor = index
        var hashes = 0
        while cursor < units.count, units[cursor] == Self.hash {
            hashes += 1
            cursor += 1
        }
        guard cursor < units.count, units[cursor] == Self.quote else { return nil }
        return (hashes, cursor)
    }

    private func delimiterIsMultiline(atQuote quoteIndex: Int) -> Bool {
        guard quoteIndex + 2 < units.count else { return false }
        return units[quoteIndex + 1] == Self.quote && units[quoteIndex + 2] == Self.quote
    }

    private func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == Self.newline || unit == 0x0D
    }

    private func isIdentifierStart(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
            .contains(scalar)
    }

    private func isIdentifierContinuation(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || isDigit(unit)
    }

    private func isDigit(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.decimalDigits.contains(scalar)
    }

    private func isHexDigit(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
    }

    private func character(from unit: UInt16) -> Character? {
        guard let scalar = UnicodeScalar(unit) else { return nil }
        return Character(scalar)
    }

    private mutating func advance(_ count: Int) {
        var remaining = count
        while remaining > 0, index < units.count {
            if units[index] == Self.newline {
                line += 1
                column = 1
            } else {
                column += 1
            }
            index += 1
            remaining -= 1
        }
    }

    /// 单次线性扫描：位置由 `advance` 维护的游标 O(1) 取得（不做 `units[..<offset]` 重算，
    /// 否则整树审计会退化成 O(tokens × offset)，实测单个集成门可拖到 275s）。
    private func currentLocation() -> SwiftSourceBoundaryAudit.SourceLocation {
        .init(path: path, line: line, column: column, utf16Offset: index)
    }
}

// MARK: - policy（只消费 token 流）

private struct Policy {
    let path: String
    let units: [UInt16]
    let tokens: [Token]

    struct Result {
        var calls: [SwiftSourceBoundaryAudit.DirectCommandCall] = []
        var violations: [SwiftSourceBoundaryAudit.Violation] = []
    }

    func evaluate() -> Result {
        var result = Result()
        var index = 0
        while index < tokens.count {
            guard case let .identifier(name) = tokens[index].kind else {
                index += 1
                continue
            }
            if name == SwiftSourceBoundaryAudit.directCommandSymbol {
                // 只排除**声明点**（`func` 紧邻的标识符），不排除同名符号的全部出现：
                // 否则 `func applyAuthoritativeFieldReadback` 会顺带白名单掉真实的成员调用。
                if isDeclarationSite(at: index) {
                    index += 1
                    continue
                }
                let location = tokens[index].location
                guard index + 1 < tokens.count,
                      tokens[index + 1].kind.isPunctuation("(") else {
                    result.violations.append(.directCommandReferenceWithoutCall(location: location))
                    index += 1
                    continue
                }
                evaluateDirectCommandCall(at: location, openParenIndex: index + 1, into: &result)
                index += 1
                continue
            }
            if name == SwiftSourceBoundaryAudit.authorityReadbackSymbol, !isDeclarationSite(at: index) {
                result.violations.append(.authorityReadbackReference(location: tokens[index].location))
            }
            index += 1
        }
        return result
    }

    /// `func` 紧邻标识符即声明点（注释 trivia 已被 tokenizer 丢弃，因此与空白无关）。
    private func isDeclarationSite(at index: Int) -> Bool {
        guard index > 0, case let .identifier(previous) = tokens[index - 1].kind else { return false }
        return previous == "func"
    }

    private func evaluateDirectCommandCall(
        at location: SwiftSourceBoundaryAudit.SourceLocation,
        openParenIndex: Int,
        into result: inout Result
    ) {
        let argument = firstArgument(after: openParenIndex)
        switch argument {
        case .unterminated:
            // 括号不闭合时不暴露半截参数文本，只给稳定的哨兵值。
            result.violations.append(.nonLiteralDirectCommand(
                location: location,
                renderedArgument: "<unterminated>"
            ))        case let .closed(significant):
            if significant.isEmpty {
                result.violations.append(.nonLiteralDirectCommand(
                    location: location,
                    renderedArgument: "<empty>"
                ))
                return
            }
            if significant.count == 1, case let .hexInteger(spelling, parsed) = significant[0].kind {
                guard let parsed else {
                    result.violations.append(.directCommandOpcodeOutOfRange(
                        location: location, spelling: spelling
                    ))
                    return
                }
                guard parsed <= 255 else {
                    result.violations.append(.directCommandOpcodeOutOfRange(
                        location: location, spelling: spelling
                    ))
                    return
                }
                result.calls.append(.init(
                    location: location,
                    opcode: UInt8(parsed),
                    spelling: spelling
                ))
                return
            }
            result.violations.append(.nonLiteralDirectCommand(
                location: location,
                renderedArgument: render(significant)
            ))
        }
    }

    private enum FirstArgument {
        case closed([Token])
        case unterminated([Token])
    }

    /// 读取第一个参数：跳过注释（已无 token），到顶层 `,` 或与调用括号配对的 `)` 为止。
    private func firstArgument(after openParenIndex: Int) -> FirstArgument {
        var depth = 0
        var significant: [Token] = []
        var index = openParenIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind.isPunctuation("(") || token.kind.isPunctuation("[") || token.kind.isPunctuation("{") {
                depth += 1
                significant.append(token)
                index += 1
                continue
            }
            if token.kind.isPunctuation(")") || token.kind.isPunctuation("]") || token.kind.isPunctuation("}") {
                if depth == 0 {
                    return .closed(significant)
                }
                depth -= 1
                significant.append(token)
                index += 1
                continue
            }
            if token.kind.isPunctuation(","), depth == 0 {
                return .closed(significant)
            }
            significant.append(token)
            index += 1
        }
        return .unterminated(significant)
    }

    /// `renderedArgument` 取**原始源码切片**（首个到末个 significant token），保留书写形态。
    private func render(_ significant: [Token]) -> String {
        guard let first = significant.first, let last = significant.last else { return "<empty>" }
        let start = first.location.utf16Offset
        let end = min(last.location.utf16Offset + last.kind.spelling.utf16.count, units.count)
        guard start < end, end <= units.count else { return "<unterminated>" }
        let slice = String(decoding: units[start ..< end], as: UTF16.self)
        let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<empty>" : trimmed
    }
}
