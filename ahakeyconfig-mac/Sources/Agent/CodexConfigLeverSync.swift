import Foundation

/// 将键盘拨杆与 Codex `~/.codex/config.toml` 顶层的 **`approval_policy`** 对齐：
/// **自动档 → `"never"`**（不弹审批，直接执行），**手动档 → `"on-request"`**（由模型
/// 在需要时暂停询问用户）。
///
/// 历史：手动档曾映射 `"untrusted"`（除已知安全只读命令外一律询问），但 Codex
/// 0.154 起已移除该取值——启动时直接报错
/// `approval_policy = "untrusted" is no longer supported; remove this setting`，
/// 导致客户端无法打开。手动档改用 `on-request`。
///
/// 取值边界：**本产品只写 `on-request` / `never` 这两个 scalar 值**（由 `ApprovalPolicy`
/// 冻结）。Codex 官方 `approval_policy` 还支持 granular 形式与其它取值，本卡不写、也不
/// 代表全局合法集合；`untrusted` 在 0.154 起不再是可写值。
///
/// 注意：项目级 `[projects."<path>"].trust_level` 只控制是否加载该项目本地的 `.codex/`
/// 配置层（config / hooks / rules），**不**决定是否弹出审批确认——那是 `approval_policy`
/// 的职责（官方文档：参见 https://developers.openai.com/codex/config-reference）。
/// 早期版本曾误以为改 `trust_level` 就能让拨杆接管 Codex，经实测无效，已改为
/// `approval_policy`。
///
/// Codex 的 `PermissionRequest` hook 协议本身不支持 `ask`/`deny`，必须像
/// `KimiPermissionModeController` 改写 Kimi 的 `default_permission_mode` 一样，
/// 直接改写 Codex 自身的审批策略开关，才能让拨杆真正接管。
///
/// 深模块边界：
/// - 唯一 raw-policy 写入口 `apply(policy:configURL:)` 是 **private**——其它 Source 文件
///   在编译期无法调用它，结构门由访问控制承担，不靠源码文本扫描。
/// - 对外 seam 只有 `apply(switchStateAuto:)`（生产，真实 `~/.codex/config.toml`）与
///   `apply(switchStateAuto:configURL:)`（测试注入 fixture）。
/// - 文件改写是**字节保真**的：只替换目标 TOML value token 的精确字节范围，或在精确
///   offset 插入；换行（LF/CRLF/CR）、行尾注释、key 周边空白与其它字节全部原样保留。
///   歧义 / 重复 key / 词法未闭合 / 非 scalar value 一律 typed fail-closed 且零写。
enum CodexConfigLeverSync {
    /// 本产品可写的审批策略集合（Codex 0.154 起 `untrusted` 不可写）。
    enum ApprovalPolicy: String, CaseIterable {
        case onRequest = "on-request"
        case never = "never"

        /// 拨杆状态 → policy：自动档 `never`，手动档 `on-request`。
        static func forLever(switchStateAuto: Bool) -> ApprovalPolicy {
            switchStateAuto ? .never : .onRequest
        }

        /// 写进 `config.toml` 的顶层键行（无缩进，与既有写入位置一致）。
        var configLine: String { "approval_policy = \"\(rawValue)\"" }
    }

    /// 同步结果。fail-safe 语义显式化：读不到 / 非 UTF-8 / 语法不受支持 / 写失败都
    /// **不改动**用户配置，且不做任何降级写入。
    enum Outcome: Equatable {
        /// 配置文件不存在：不创建。
        case missingConfig
        /// 读取失败或非 UTF-8：不动。
        case unreadableConfig
        /// 已是目标值：幂等早退，零字节变化。
        case alreadyDesired
        /// 只替换了既有 value token。
        case replaced
        /// 在首个真 table header 前（或文件末尾）插入。
        case inserted
        /// 原子写失败：不动。
        case writeFailed
        /// 顶层出现多个 `approval_policy`：歧义，零写。
        case duplicateKey
        /// 词法未闭合 / 非 scalar value / 无法安全定位：零写。
        case unsupportedSyntax(reason: String)
    }

    /// 生产配置路径；测试一律注入临时 fixture URL，绝不触碰用户真实 home。
    static var productionConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml", isDirectory: false)
    }

    /// 生产入口：`CodexSessionStart` / `CodexPermissionRequest` 的唯一 seam。
    static func apply(switchStateAuto: Bool) {
        _ = apply(
            policy: ApprovalPolicy.forLever(switchStateAuto: switchStateAuto),
            configURL: productionConfigURL
        )
    }

    /// 测试注入入口：同样的 typed seam，只是换 fixture URL。
    @discardableResult
    static func apply(switchStateAuto: Bool, configURL: URL) -> Outcome {
        apply(policy: ApprovalPolicy.forLever(switchStateAuto: switchStateAuto), configURL: configURL)
    }

    /// 唯一 raw-policy 写入口。`private`（文件私有）⇒ 其它 Source 文件编译期不可调用，
    /// 因此不存在「绕过拨杆 seam 直接写任意 policy」的路径。
    private static func apply(policy: ApprovalPolicy, configURL: URL) -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return .missingConfig }
        guard let data = fm.contents(atPath: configURL.path),
              String(data: data, encoding: .utf8) != nil else { return .unreadableConfig }
        let bytes = [UInt8](data)

        switch TomlPolicyLocator.locate(bytes) {
        case let .failure(failure):
            switch failure {
            case .duplicateKey:
                return .duplicateKey
            case let .unsupported(reason):
                return .unsupportedSyntax(reason: reason)
            }

        case let .success(selection):
            switch selection {
            case let .existing(valueRange, value):
                if value == policy.rawValue { return .alreadyDesired }
                var out = bytes
                out.replaceSubrange(valueRange, with: Array("\"\(policy.rawValue)\"".utf8))
                return write(out, to: configURL) ? .replaced : .writeFailed

            case let .absent(offset, prefix, suffix):
                var insertion = prefix
                insertion.append(contentsOf: Array(policy.configLine.utf8))
                insertion.append(contentsOf: suffix)
                var out = bytes
                out.insert(contentsOf: insertion, at: offset)
                return write(out, to: configURL) ? .inserted : .writeFailed
            }
        }
    }

    private static func write(_ bytes: [UInt8], to url: URL) -> Bool {
        do {
            try Data(bytes).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - byte-preserving TOML locator

/// 单次、字节保真的 TOML 顶层定位器：找出顶层 `approval_policy` 的 value token 字节范围，
/// 或在首个**真** table header 前给出插入 offset。它是本文件唯一的 TOML 解析路径。
///
/// 关键区分：`[` 只有在「语句起始、且不在任何 value 内部」时才是 table header；
/// 多行 basic/literal string、跨行 array / inline table、注释里的 `[` 一律被正确跳过。
/// 任何无法安全判定的输入（词法未闭合、重复 key、非 scalar value）都返回 typed failure，
/// 调用方零写。
private enum TomlPolicyLocator {
    enum Failure: Error, Equatable {
        case duplicateKey
        case unsupported(String)
    }

    enum Selection {
        /// 已存在的顶层 `approval_policy`：只替换这段 value token 字节。
        case existing(valueRange: Range<Int>, value: String)
        /// 缺键：在 `offset` 处插入 `prefix + <key line> + suffix`。
        case absent(offset: Int, prefix: [UInt8], suffix: [UInt8])
    }

    static func locate(_ bytes: [UInt8]) -> Result<Selection, Failure> {
        var scanner = Scanner(bytes: bytes)
        do {
            try scanner.scan()
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.unsupported("扫描失败"))
        }

        if let policy = scanner.policy {
            return .success(.existing(valueRange: policy.range, value: policy.value))
        }
        let newline = scanner.newlineStyle
        if let tableStart = scanner.firstTableLineStart {
            return .success(.absent(offset: tableStart, prefix: [], suffix: newline))
        }
        if bytes.isEmpty || Scanner.isNewline(bytes[bytes.count - 1]) {
            return .success(.absent(offset: bytes.count, prefix: [], suffix: newline))
        }
        return .success(.absent(offset: bytes.count, prefix: newline, suffix: []))
    }

    private struct Scanner {
        static let tab: UInt8 = 0x09
        static let space: UInt8 = 0x20
        static let lf: UInt8 = 0x0A
        static let cr: UInt8 = 0x0D
        static let hash: UInt8 = 0x23
        static let equals: UInt8 = 0x3D
        static let dot: UInt8 = 0x2E
        static let quote: UInt8 = 0x22
        static let apostrophe: UInt8 = 0x27
        static let lbracket: UInt8 = 0x5B
        static let rbracket: UInt8 = 0x5D
        static let lbrace: UInt8 = 0x7B
        static let rbrace: UInt8 = 0x7D
        static let comma: UInt8 = 0x2C
        static let backslash: UInt8 = 0x5C

        enum Value {
            /// 单行 basic / literal 字符串（可安全定位并替换）。
            case scalarString(range: Range<Int>, decoded: String)
            /// 其它语法上合法的 value（array / inline table / 数字 / bool / 多行字符串 …）。
            case other
        }

        let bytes: [UInt8]
        var index = 0
        var inTable = false
        var firstTableLineStart: Int?
        var policy: (range: Range<Int>, value: String)?
        var newlineStyle: [UInt8] = [Scanner.lf]

        init(bytes: [UInt8]) {
            self.bytes = bytes
            self.newlineStyle = Scanner.detectNewlineStyle(bytes)
        }

        static func isNewline(_ byte: UInt8) -> Bool { byte == lf || byte == cr }

        static func detectNewlineStyle(_ bytes: [UInt8]) -> [UInt8] {
            for (offset, byte) in bytes.enumerated() {
                if byte == cr {
                    let next = offset + 1 < bytes.count ? bytes[offset + 1] : nil
                    return next == lf ? [cr, lf] : [cr]
                }
                if byte == lf { return [lf] }
            }
            return [lf]
        }

        // MARK: main loop

        mutating func scan() throws {
            while index < bytes.count {
                skipHorizontalWhitespace()
                guard index < bytes.count else { break }
                let byte = bytes[index]
                if Scanner.isNewline(byte) {
                    consumeNewline()
                    continue
                }
                if byte == Scanner.hash {
                    skipToLineEnd()
                    continue
                }
                if byte == Scanner.lbracket {
                    // 只有语句起始处的 `[` 才是 table header；value 内部的 `[` 由
                    // parseValue 消费，永远不会走到这里。
                    if firstTableLineStart == nil { firstTableLineStart = lineStart(containing: index) }
                    inTable = true
                    try parseTableHeader()
                    continue
                }
                try parseKeyValue()
            }
        }

        // MARK: statements

        private mutating func parseTableHeader() throws {
            index += 1 // '['
            if index < bytes.count, bytes[index] == Scanner.lbracket { index += 1 }
            var closed = false
            while index < bytes.count {
                let byte = bytes[index]
                if Scanner.isNewline(byte) { throw Failure.unsupported("table header 跨行") }
                if byte == Scanner.quote {
                    _ = try scanBasicStringOnLine()
                    continue
                }
                if byte == Scanner.apostrophe {
                    _ = try scanLiteralStringOnLine()
                    continue
                }
                if byte == Scanner.rbracket {
                    index += 1
                    if index < bytes.count, bytes[index] == Scanner.rbracket { index += 1 }
                    closed = true
                    break
                }
                index += 1
            }
            guard closed else { throw Failure.unsupported("table header 未闭合") }
            skipHorizontalWhitespace()
            if index < bytes.count, bytes[index] == Scanner.hash {
                skipToLineEnd()
            } else if index < bytes.count, !Scanner.isNewline(bytes[index]) {
                throw Failure.unsupported("table header 后有额外内容")
            }
        }

        private mutating func parseKeyValue() throws {
            let keyPath = try parseKeyPath()
            skipHorizontalWhitespace()
            guard index < bytes.count, bytes[index] == Scanner.equals else {
                throw Failure.unsupported("key 后缺少 '='")
            }
            index += 1
            skipHorizontalWhitespace()
            let value = try parseValue()
            skipHorizontalWhitespace()
            if index < bytes.count, bytes[index] == Scanner.hash {
                skipToLineEnd()
            } else if index < bytes.count, !Scanner.isNewline(bytes[index]) {
                throw Failure.unsupported("value 后有额外内容")
            }

            guard !inTable, keyPath == ["approval_policy"] else { return }
            guard policy == nil else { throw Failure.duplicateKey }
            guard case let .scalarString(range, decoded) = value else {
                throw Failure.unsupported("approval_policy 的 value 不是单行 scalar 字符串")
            }
            policy = (range, decoded)
        }

        private mutating func parseKeyPath() throws -> [String] {
            var parts: [String] = []
            while true {
                skipHorizontalWhitespace()
                guard index < bytes.count else { throw Failure.unsupported("key 意外结束") }
                let byte = bytes[index]
                if byte == Scanner.quote {
                    parts.append(try scanBasicStringOnLine().decoded)
                } else if byte == Scanner.apostrophe {
                    parts.append(try scanLiteralStringOnLine().decoded)
                } else if Scanner.isBareKeyByte(byte) {
                    let start = index
                    while index < bytes.count, Scanner.isBareKeyByte(bytes[index]) { index += 1 }
                    parts.append(String(decoding: bytes[start..<index], as: UTF8.self))
                } else {
                    throw Failure.unsupported("非法 key")
                }
                skipHorizontalWhitespace()
                if index < bytes.count, bytes[index] == Scanner.dot {
                    index += 1
                    continue
                }
                break
            }
            return parts
        }

        // MARK: values

        private mutating func parseValue() throws -> Value {
            guard index < bytes.count else { throw Failure.unsupported("缺少 value") }
            let byte = bytes[index]
            if byte == Scanner.quote {
                if isTriple(at: index) {
                    try scanMultilineBasicString()
                    return .other
                }
                let scanned = try scanBasicStringOnLine()
                return .scalarString(range: scanned.range, decoded: scanned.decoded)
            }
            if byte == Scanner.apostrophe {
                if isTriple(at: index) {
                    try scanMultilineLiteralString()
                    return .other
                }
                let scanned = try scanLiteralStringOnLine()
                return .scalarString(range: scanned.range, decoded: scanned.decoded)
            }
            if byte == Scanner.lbracket {
                try scanArray()
                return .other
            }
            if byte == Scanner.lbrace {
                try scanInlineTable()
                return .other
            }
            try scanBareValue()
            return .other
        }

        private mutating func scanSingleLineString(terminator: UInt8, allowEscapes: Bool) throws
            -> (range: Range<Int>, decoded: String) {
            let start = index
            index += 1 // opening quote
            var out: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                if byte == terminator {
                    let stop = index + 1
                    index = stop
                    return (start..<stop, String(decoding: out, as: UTF8.self))
                }
                if Scanner.isNewline(byte) { throw Failure.unsupported("字符串未闭合") }
                if allowEscapes, byte == Scanner.backslash {
                    index += 1
                    guard index < bytes.count else { throw Failure.unsupported("转义未结束") }
                    switch bytes[index] {
                    case Scanner.quote: out.append(Scanner.quote); index += 1
                    case Scanner.backslash: out.append(Scanner.backslash); index += 1
                    case 0x62: out.append(0x08); index += 1
                    case 0x66: out.append(0x0C); index += 1
                    case 0x6E: out.append(0x0A); index += 1
                    case 0x72: out.append(0x0D); index += 1
                    case 0x74: out.append(Scanner.tab); index += 1
                    case 0x75: out.append(contentsOf: Array(String(try scanHexScalar(digits: 4)).utf8))
                    case 0x55: out.append(contentsOf: Array(String(try scanHexScalar(digits: 8)).utf8))
                    default: throw Failure.unsupported("未知的字符串转义")
                    }
                    continue
                }
                out.append(byte)
                index += 1
            }
            throw Failure.unsupported("字符串未闭合")
        }

        private mutating func scanBasicStringOnLine() throws -> (range: Range<Int>, decoded: String) {
            try scanSingleLineString(terminator: Scanner.quote, allowEscapes: true)
        }

        private mutating func scanLiteralStringOnLine() throws -> (range: Range<Int>, decoded: String) {
            try scanSingleLineString(terminator: Scanner.apostrophe, allowEscapes: false)
        }

        private mutating func scanHexScalar(digits: Int) throws -> UnicodeScalar {
            guard index + digits <= bytes.count else { throw Failure.unsupported("unicode 转义被截断") }
            var value: UInt32 = 0
            for _ in 0..<digits {
                guard let digit = Scanner.hexDigit(bytes[index]) else {
                    throw Failure.unsupported("unicode 转义非法")
                }
                value = value << 4 | UInt32(digit)
                index += 1
            }
            guard let scalar = UnicodeScalar(value) else { throw Failure.unsupported("unicode 标量非法") }
            return scalar
        }

        private mutating func scanMultilineBasicString() throws {
            index += 3
            while index < bytes.count {
                let byte = bytes[index]
                if byte == Scanner.backslash {
                    index += 1
                    if index < bytes.count { index += 1 }
                    continue
                }
                if byte == Scanner.quote {
                    var run = 0
                    while index < bytes.count, bytes[index] == Scanner.quote { run += 1; index += 1 }
                    if run >= 3 { return }
                    continue
                }
                index += 1
            }
            throw Failure.unsupported("多行 basic 字符串未闭合")
        }

        private mutating func scanMultilineLiteralString() throws {
            index += 3
            while index < bytes.count {
                let byte = bytes[index]
                if byte == Scanner.apostrophe {
                    var run = 0
                    while index < bytes.count, bytes[index] == Scanner.apostrophe { run += 1; index += 1 }
                    if run >= 3 { return }
                    continue
                }
                index += 1
            }
            throw Failure.unsupported("多行 literal 字符串未闭合")
        }

        private mutating func scanArray() throws {
            index += 1 // '['
            while true {
                skipWhitespaceCommentsAndNewlines()
                guard index < bytes.count else { throw Failure.unsupported("array 未闭合") }
                if bytes[index] == Scanner.rbracket { index += 1; return }
                _ = try parseValue()
                skipWhitespaceCommentsAndNewlines()
                guard index < bytes.count else { throw Failure.unsupported("array 未闭合") }
                if bytes[index] == Scanner.comma { index += 1; continue }
                if bytes[index] == Scanner.rbracket { index += 1; return }
                throw Failure.unsupported("array 内缺少 ',' 或 ']'")
            }
        }

        private mutating func scanInlineTable() throws {
            index += 1 // '{'
            while true {
                skipWhitespaceCommentsAndNewlines()
                guard index < bytes.count else { throw Failure.unsupported("inline table 未闭合") }
                if bytes[index] == Scanner.rbrace { index += 1; return }
                _ = try parseKeyPath()
                skipHorizontalWhitespace()
                guard index < bytes.count, bytes[index] == Scanner.equals else {
                    throw Failure.unsupported("inline table 内缺少 '='")
                }
                index += 1
                skipHorizontalWhitespace()
                _ = try parseValue()
                skipWhitespaceCommentsAndNewlines()
                guard index < bytes.count else { throw Failure.unsupported("inline table 未闭合") }
                if bytes[index] == Scanner.comma { index += 1; continue }
                if bytes[index] == Scanner.rbrace { index += 1; return }
                throw Failure.unsupported("inline table 内缺少 ',' 或 '}'")
            }
        }

        private mutating func scanBareValue() throws {
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if Scanner.isNewline(byte) || byte == Scanner.comma
                    || byte == Scanner.rbracket || byte == Scanner.rbrace
                    || byte == Scanner.hash {
                    break
                }
                index += 1
            }
            if index == start { throw Failure.unsupported("空 value") }
        }

        // MARK: primitives

        private func isTriple(at offset: Int) -> Bool {
            offset + 2 < bytes.count && bytes[offset + 1] == bytes[offset] && bytes[offset + 2] == bytes[offset]
        }

        private mutating func skipHorizontalWhitespace() {
            while index < bytes.count, bytes[index] == Scanner.space || bytes[index] == Scanner.tab {
                index += 1
            }
        }

        private mutating func skipToLineEnd() {
            while index < bytes.count, !Scanner.isNewline(bytes[index]) { index += 1 }
        }

        private mutating func skipWhitespaceCommentsAndNewlines() {
            while index < bytes.count {
                let byte = bytes[index]
                if byte == Scanner.space || byte == Scanner.tab {
                    index += 1
                    continue
                }
                if Scanner.isNewline(byte) {
                    consumeNewline()
                    continue
                }
                if byte == Scanner.hash {
                    skipToLineEnd()
                    continue
                }
                break
            }
        }

        private mutating func consumeNewline() {
            if bytes[index] == Scanner.cr {
                index += 1
                if index < bytes.count, bytes[index] == Scanner.lf { index += 1 }
            } else if bytes[index] == Scanner.lf {
                index += 1
            }
        }

        private func lineStart(containing offset: Int) -> Int {
            var cursor = offset
            while cursor > 0 {
                let previous = bytes[cursor - 1]
                if previous == Scanner.lf || previous == Scanner.cr { break }
                cursor -= 1
            }
            return cursor
        }

        private static func isBareKeyByte(_ byte: UInt8) -> Bool {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x5F, 0x2D: return true
            default: return false
            }
        }

        private static func hexDigit(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: return byte - 0x30
            case 0x41...0x46: return byte - 0x41 + 10
            case 0x61...0x66: return byte - 0x61 + 10
            default: return nil
            }
        }
    }
}
