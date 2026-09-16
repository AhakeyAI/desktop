# C5IR8 技术设计：Swift Source Boundary Audit 深模块

日期：2026-09-16
状态：冻结执行方案
执行：DSH
验收：Codex
范围：C5IR8，tests/docs-only，`ahakeyconfig-mac/Sources/**` 零改

## 1. 结论

C5IR4–C5IR7 反复失败不是单个 case 漏写，而是模块形状错误：一个需要理解 Swift 词法和局部语法的安全门，被实现成巨型 endpoint 测试文件里的「删除文本 → 正则匹配」浅层 helper。每轮修一个反例，却没有一个有限、完整、可枚举的状态模型，所以下一轮必然暴露另一个组合。

C5IR8 不再向旧 helper 追加分支。它必须把 scanner + policy 收成一个 **深模块**：调用方只知道 `audit(sources:) -> Report`，词法状态、token、声明识别、参数闭合和 fail-closed 全部藏在模块内。

## 2. 反复失败的核心规律

### 2.1 只修审查反例，没有修表示法

- IR4 修「首 token」，但仍是 regex 读调用。
- IR5 修 raw multiline，但仍用「删掉字符串」作表示法，因而删掉可执行 interpolation。
- IR6 加 mode stack，但 interpolation 没有深度，遇第一个 `)` 就退出。
- IR7 加深度，但 EOF 只看栈顶，line-comment 可掩盖未闭合底栈。

共同特征：新代码能通过「当轮新增的几行」，但没有一个不变式证明所有状态组合。

### 2.2 临时 mutant 代替了永久回归

evidence 中的 patch→run→restore 只证明当时某个 mutant 会红；它不会阻止未来退化。多次回传把「临时红过」写成「永久闭合」，但任务卡点名的矩阵没有真正提交。

### 2.3 测试穿过内部 helper，没有稳定 interface

`strippingCommentsAndStrings`、`realSymbolReferenceCount`、`directCommandCallsites`三个 helper 各自暴露内部细节，测试也分别锁内部实现。这是浅层模块：实现复杂度泄漏给每个调用方和每个测试。

### 2.4 覆盖是人工列表，不是机器空间

需要覆盖的维度其实已知：

- string form：ordinary single/multiline，raw single/multiline；
- hash level：0/1/2；
- protected symbol：direct command / authority readback；
- prefix expression：nested call / tuple / closure；
- termination：normal / line-comment EOF / malformed stack。

但旧测试一直手写少数 rows，因此每轮都会漏一个维度交叉。

## 3. C5IR8 模块设计

### 3.1 文件布局

允许新增：

- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/Support/SwiftSourceBoundaryAudit.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/SwiftSourceBoundaryAuditTests.swift`

保留 `AhaKeyAgentRuntimeEndpointTests.swift` 里只有一个产品树 integration test。旧 scanner/helper/matrix 全部从该巨型文件删除，不得「新模块 + 旧 helper」双轨保留。这是 replace，不是 layer。

`Package.swift` 不需修改；test target 会自动编译 `Tests/AhaKeyAgentTests/**.swift`。

### 3.2 唯一对外 interface

```swift
struct SwiftSourceBoundaryAudit {
    struct SourceFile: Equatable {
        let path: String
        let bytes: [UInt8]

        init(path: String, bytes: [UInt8])
        init(path: String, text: String) // tests convenience; stores UTF-8 bytes
    }

    struct SourceLocation: Equatable, Comparable {
        let path: String
        let line: Int       // 1-based
        let column: Int     // 1-based UTF-16 column
        let utf16Offset: Int
    }

    struct DirectCommandCall: Equatable {
        let location: SourceLocation
        let opcode: UInt8
        let spelling: String
    }

    struct CompleteReport: Equatable {
        let calls: [DirectCommandCall]       // location-sorted
        let violations: [Violation]          // location-sorted
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

    enum Violation: Equatable {
        case malformedSource(location: SourceLocation, reason: LexicalFailure)
        case directCommandReferenceWithoutCall(location: SourceLocation)
        case nonLiteralDirectCommand(location: SourceLocation, renderedArgument: String)
        case directCommandOpcodeOutOfRange(location: SourceLocation, spelling: String)
        case authorityReadbackReference(location: SourceLocation)
    }

    static func audit(_ sources: [SourceFile]) -> Report
}
```

调用方和测试不得调用 tokenizer、mode stack、declaration range 或 argument parser。这些全是模块 implementation。`audit` 内部首先按 `path` 排序 sources，所有 calls/violations 按 `SourceLocation` 排序，保证消息稳定。

**多文件 malformed 语义冻结**：任一文件为非 UTF-8 或词法未闭合，整个 audit 必须返回 `.malformed`，`isClean == false`，不得返回 `.complete`。模块可继续扫描其它文件以收集全部 typed diagnostics，但 `.malformed` 不暴露 calls/opcode multiset，不存在「跳过坏文件后 inventory 变短」的可表示状态。

### 3.3 内部 token 模型

不再生成「剥离后的 String」。scanner 一次输出 code/interpolation 中的 token：

```swift
private enum TokenKind: Equatable {
    case identifier(String)
    case hexInteger(spelling: String, parsed: UInt64?)
    case punctuation(Character) // ( ) [ ] { } , . :
    case other(String)
}

private struct Token: Equatable {
    let kind: TokenKind
    let location: SwiftSourceBoundaryAudit.SourceLocation
}
```

注释和字符串纯文本不产生 token；interpolation expression 递归产生正常 token。这样 declaration/call/argument 分析消费同一 token 流，不再一边用 regex、一边用字符偏移。非 UTF-8 bytes 在 tokenization 前转为 `.malformedSource(reason: .invalidUTF8)`，不抛出、不崩溃。

### 3.4 状态机

```swift
private enum Mode {
    case code
    case lineComment(parent: ParentMode)
    case blockComment(parent: ParentMode, depth: Int)
    case string(StringDelimiter)
    case interpolation(StringDelimiter, parenDepth: Int)
}
```

`StringDelimiter` 同时冻结：

- ordinary/raw；
- single/multiline；
- raw hash count；
- 精确 terminator；
- 精确 interpolation prefix。

必须保持以下不变式：

1. root 永远是 `.code`，不被替换。
2. interpolation 初始 `parenDepth=1`；仅 code/interpolation 中的 `(` / `)` 改深度；字符串和注释内不改。
3. `parenDepth` 归零时只弹出本 interpolation，返回它的 string parent。
4. line comment 在换行或 EOF 结束。EOF 时先弹出尾部 line comment，然后栈必须**精确**为 `[code]`。
5. EOF 时任何 string/block/interpolation 残留都产生 typed `malformedSource`，不返回部分 token。
6. raw interpolation 只接受与 delimiter hash count 精确相等的 prefix；较低/较高 hash 序列是文本。
7. nested block comment 以 depth 闭合；EOF depth>0 必须拒绝。
8. 文件枚举和输出均按 path/location 排序；扫描结果不依赖文件系统遍历顺序。

### 3.5 policy 算法

scanner 成功后，policy 只消费 token：

1. 遇 `identifier("func")` + 下一 identifier 时记录函数声明名；不再使用 whitespace regex。
2. 遇 `sendDirectCommandFrame` 声明名：跳过。
3. 遇非声明 `sendDirectCommandFrame`：
   - 下一 token 必须是 `(`，否则 `directCommandReferenceWithoutCall`；
   - 注释是 trivia：`sendDirectCommandFrame(/*c*/ 0x00)` 与 `sendDirectCommandFrame(0x00 /*c*/)` 允许，因为第一参数的唯一 significant token 仍是 hex；
   - 第一参数必须精确为一个 `hexInteger`，且数值在 `0...255`；`0x100` 或无法转成 `UInt64` 的超大字面量为 `directCommandOpcodeOutOfRange`；
   - 任何其它 token、表达式或 malformed delimiter 都是 `nonLiteralDirectCommand`；空/纯空白参数的 `renderedArgument` 固定为 `<empty>`。
4. 遇 `applyAuthoritativeFieldReadback` 声明名：跳过。
5. 遇任何其它 `applyAuthoritativeFieldReadback` token：`authorityReadbackReference`。
6. 最终产品树唯一允许的 direct opcode multiset 精确为 `[0x00, 0x94]`，`violations` 必须为空。该期望常量只放在 `AhaKeyAgentRuntimeEndpointTests` 的 integration gate，来源注释固定为：`0x00` = 周期状态轮询，`0x94` = legacy task-picture 探测。失败消息必须打印所有 `DirectCommandCall` 的 path/line/column/spelling，而不只打 opcode 数组。

如果 tokenization 或 policy 不能证明某个形状，必须拒绝，不得猜测为 clean。

## 4. 一次性反馈环

### 4.1 先红后改

DSH 已在当前工作区建立 `unterminated-interpolation-masked-by-line-comment`，并用忠实还原 `c47a87b` EOF 逻辑的 mutant 证明「未抛错」稳定变红。Codex 接受这份已有红环，**不要重写一条一次性临时测试**。

建立新模块时，直接把同一最小输入迁到 `SwiftSourceBoundaryAuditTests.swift`，通过新 interface 断言 typed violation，然后删除旧-helper 版本：

```swift
let source = ##"let s = "\(foo // EOF"##
let report = SwiftSourceBoundaryAudit.audit([.init(path: "fixture.swift", text: source)])
guard case let .malformed(violations) = report else {
    return XCTFail("EOF-under-interpolation must make the whole audit malformed")
}
XCTAssertEqual(violations, [
    .malformedSource(location: /* frozen line/column */, reason: .unterminatedInterpolation(depth: 1))
])
```

紧反馈命令：

```bash
cd ahakeyconfig-mac
swift test --filter SwiftSourceBoundaryAuditTests
```

要求：evidence 保留 DSH 已录取的旧-helper 红日志；实现后同一输入通过新 interface 变绿，且整类在数秒内完成。

### 4.2 机器生成矩阵，不手写漏组合

这里的 fixture 统一称为 **auditable source**：它必须是词法/语法可扫描的 Swift 形状，但不要求通过 type-check。`sendDirectCommandFrame` 返回 `Void`、authority actor 隔离和真实参数标签不属于本词法模块的 oracle；文档不再宣称 fixture 是 executable。

定义八种 string form：

1. ordinary single
2. ordinary multiline
3. raw `#` single
4. raw `#` multiline
5. raw `##` single
6. raw `##` multiline
7. raw `###` single
8. raw `###` multiline

两种 protected symbol：

1. `sendDirectCommandFrame(0x96)`
2. `store.applyAuthoritativeFieldReadback(deviceID: d, pageID: p, fieldID: f, value: v, version: ver)`

三种 prefix expression：

1. `helper() +`
2. `(helper(), 0).1 +`
3. `{ helper() }() +`

测试必须以循环生成 `8 × 2 × 3 = 48` 个 protected interpolation auditable rows，而不是手写少数行。生成器必须先自校验：

1. `Set(generatedSources).count == 48`；
2. 每个 command row 必须产生恰一条对应 direct-command violation，每个 authority row 必须产生恰一条 authority violation；
3. 每种 raw form 生成一字符负对照：把 interpolation prefix 的 hash 数改低或改高一位，结果必须从 protected 翻转为 benign；ordinary form 去掉反斜杠后同样必须翻转。

另生成对称 benign 矩阵：相同 protected symbol 文本出现在纯字符串片段、line comment、nested block comment 中时必须零违规。benign sources 同样必须唯一，且每行必须显式断言 zero violations，防止生成器空转或把「不漏检」修成「全假红」。

### 4.3 状态转移矩阵

永久测试至少覆盖：

- root line comment at EOF → success；
- ordinary/raw interpolation 内 line comment at EOF → malformed interpolation；
- string 内 nested interpolation 再嵌 string/comment/interpolation → protected symbol 可见；
- raw hash count 1/2/3：精确 hash 才进 interpolation，其它均是文本；
- 对 hash 1/2/3 分别覆盖「较低一位」与「较高一位」前缀是文本；
- unterminated ordinary/multiline/raw string；
- unterminated nested block comment（depth 1/2）；
- unterminated interpolation（depth 1/2）；
- mismatched `()[]{}` direct-command first argument → violation；
- declaration whitespace `space/double-space/tab/newline/comment-as-trivia` → 只排除声明本身；
- direct-command argument comments 为 trivia：`/*c*/ 0x00`、`0x00 /*c*/`、line-comment+换行均接受；
- `0x100` 与超出 `UInt64` 的 hex → `directCommandOpcodeOutOfRange`；
- 空/纯空白参数 → `nonLiteralDirectCommand(renderedArgument: "<empty>")`；
- 非 UTF-8 source → whole-audit `.malformed`；
- reference without call → violation。

### 4.4 旧回归迁移账本

不得以「新矩阵是 superset」口头删除旧证据。在 `SwiftSourceBoundaryAuditTests` 中定义 `LegacyRegressionID` enum，以集合等式证明下列每个已验收行都有新 interface 用例：

| 旧回归/语义 | 新稳定 case ID |
|---|---|
| literal / literal-with-newline | `direct.literal`, `direct.literal-newline` |
| variable / `0x00 \| 0x96` / `(0x00)` / `Self.opcode()` | `direct.variable`, `direct.binary`, `direct.parenthesized`, `direct.function-result` |
| array/dictionary/closure/subscript first argument | `direct.array`, `direct.dictionary`, `direct.closure`, `direct.subscript` |
| unmatched paren/bracket/brace | `direct.unterminated-paren`, `direct.unterminated-bracket`, `direct.unterminated-brace` |
| `<reference-without-call>` | `direct.reference-without-call` |
| declaration single/double/tab/newline/default args + declaration-and-call | `declaration.*` |
| authority direct/alias + `Extra`/`V2` non-match | `authority.*` |
| ordinary/multiline/raw string termination | `lexical.string-termination.*` |
| nested block comments | `lexical.block-comment-depth.*` |
| interpolation depth/nested string/nested array | `lexical.interpolation.*` |
| `raw-multiline-with-inner-hash-quote` | `raw.hash1.multiline.inner-hash-quote` |
| `raw-multiline-does-not-hide-following-code` | `raw.hash1.multiline.following-code` |
| `raw-double-hash-lower-hash-prefix-is-text` | `raw.hash2.lower-prefix-text` |
| top-level five typed EOF failures | `malformed.string-ordinary`, `malformed.string-multiline`, `malformed.string-raw`, `malformed.block`, `malformed.interpolation` |
| trailing root line-comment success / masked interpolation failure | `eof.root-line-comment`, `eof.interpolation-line-comment` |

机械门：`Set(migratedLegacyIDs) == Set(LegacyRegressionID.allCases)`，且新模块回归数不小于删除的旧永久 rows 数。迁移账本与机器生成矩阵是两个独立门；不得用其中一个替代另一个。

## 5. 实施顺序

1. **冻结现场**：执行基线为「包含本终版设计的 Codex 冻结提交」（parent `af48d21`，完整 SHA 以 Codex 回传为准）；产品语义基线为 `c47a87b`。先记录 `git status --short`，明确保留范围外 `CodexConfigLeverSync.swift`。
2. **复用红环**：保留 DSH 已完成的 `unterminated-interpolation-masked-by-line-comment` + 忠实 EOF mutant 红日志；把同一输入迁到新 interface，不再重写一次性红测试。
3. **建深模块**：在 `Support/SwiftSourceBoundaryAudit.swift` 一次完成 tokenizer/state machine/policy；不改 Sources。
4. **替换而非叠加**：把 endpoint 产品树 gate 改成一次 `audit`；删除旧 stripper/regex/argument helpers 及穿过内部的旧矩阵。
5. **跑机器矩阵**：48 protected + 对称 benign + 一字符翻转 + 状态矩阵 + 旧回归迁移账本全绿；产品树集成 gate 精确得到 `[0x00, 0x94]` + zero violations，失败输出具名 callsite。
6. **反证**：不修产品 Sources，只在 fixture 中证明：去 depth、接受底栈 line-comment、误把 lower-hash 当 interpolation、允许 reference-without-call 任一 mutant 都会使永久矩阵变红。反证结束必须 restore+sha。
7. **门禁**：新测试类、C5I 定向 19 类、全量 Swift、App+Agent Release、identity；`git diff --check <C5IR8-base>...<C5IR8-commit>` 与本轮工作树 diff 必须全绿。`5d1fe1d...HEAD` 的已知红点来自 `af48d21`/15K-J 文档，不作为 C5IR8 失败，但 evidence 必须指名归属，不得声称全范围 diff-check 绿。
8. **白名单提交**：只包含两个 test 文件/必要 endpoint test 减删、evidence、本任务卡。不包含 `CodexConfigLeverSync.swift`、15K-J 产品改动、queue/board 他人 diff。

## 6. 验收硬门

C5IR8 只在以下全部成立时 accepted：

- [ ] 外部 interface 只有 `audit(sources:) -> Report`；测试不穿过 tokenizer/mode stack。
- [ ] 旧 stripper/regex/callsite helper 已删除，不双轨。
- [ ] `Report` 提供 per-callsite path/line/column/opcode/spelling，opcode multiset 仅为派生值。
- [ ] 任一 malformed/invalid UTF-8 使**整个** audit 返回 `.malformed` 且 `isClean == false`，不可访问缩短 inventory。
- [ ] 48 个 auditable interpolation 交叉用例唯一且全绿，每行恰一对应 violation。
- [ ] 对称 benign 矩阵全绿，每行 zero violations；一字符 hash/反斜杠变异使结果翻转。
- [ ] EOF 尾部 line-comment 归一后，只有 `[code]` 可成功。
- [ ] 旧回归迁移账本集合等式成立；新 rows 数不小于被删旧 rows。
- [ ] opcode 越界、comment-as-trivia、`<empty>`、hash 1/2/3 高低前缀、非 UTF-8 全部有永久行。
- [ ] 产品树 report 精确为 opcodes `[0x00, 0x94]` 且 zero violations；两个 callsite 带 path/line/column 与用途注释。
- [ ] `git diff <base>...<commit> -- ahakeyconfig-mac/Sources` 为空。
- [ ] 定向/全量/Release/identity 全绿；C5IR8 增量/working diff-check 全绿，已知 15K-J 历史红点具名披露。

## 7. 停止与接管规则

- DSH 不得继续在旧 helper 上补第八轮 if/regex；如无法在本设计 interface 下完成，立即停手说明具体阻塞。
- 不得用「通用实现看似能覆盖」替代机器矩阵。
- 不得以临时 mutant 日志替代永久回归。
- 如 C5IR8 下一次审查仍有任一 blocking finding，DSH 停止继续返工；由 Codex 直接接管实现和验证。
- C5IR8 accepted 前，15K-J 保持 draft，R7/HIL/签名/设备写全部关闭。

## 8. 对 DSH 设计评审的逐项裁决

| DSH 条目 | 裁决 |
|---|---|
| §2.1 per-callsite provenance | **采纳**：`DirectCommandCall` 带 path/line/column/opcode/spelling，multiset 只是派生值。 |
| §2.2 malformed 全局语义 | **采纳并强化**：`Report` 为 `.complete/.malformed` 互斥枚举；任一 malformed 使整个 audit 非 clean，malformed report 不暴露 calls。 |
| §2.3 旧行迁移表 | **采纳**：§4.4 冻结具名账本 + `LegacyRegressionID` 集合等式 + rows 不缩水。 |
| §2.4 生成器自校验 | **采纳**：唯一性、每行精确 violation/zero violation、一字符翻转三门。 |
| §3.1 executable 未定义 | **采纳语义更正**：统一称 auditable source，不宣称 type-check/executable；authority 形状改用真参数标签。 |
| §3.2 hex 越界 | **采纳**：`directCommandOpcodeOutOfRange`，覆盖 `0x100` 和超 `UInt64`。 |
| §3.3 argument comment trivia | **采纳并定义为允许**：注释不改变唯一 significant hex token。 |
| §3.4 hash-3/更高前缀 | **采纳并扩维**：形态扩为 8 种，protected 矩阵扩为 48；hash 1/2/3 高低前缀均有 benign 反例。 |
| §3.5 location/空参数 | **采纳**：所有 finding 带 1-based line/UTF-16 column/offset；空参数渲染 `<empty>`。 |
| §3.6 期望常量来源 | **采纳**：只在 integration gate 冻结 `[0x00,0x94]`，注释标明状态轮询/legacy 探测，失败打印 callsites。 |
| §3.7 排序/编码 | **采纳**：模块内 path/location 排序；`SourceFile` 收 bytes；非 UTF-8 是 typed malformed，不抛出/崩溃。 |
| §4.1 已有红环 | **接受复用**：保留已录红日志，直接迁移同一输入，不再写一次性临时测试。 |
| §4.3 endpoint test 净减 | **确认允许且必须**：replace-don't-layer，只留 integration gate。 |
| §4.4 diff-check 范围 | **采纳**：C5IR8 增量与 working diff 必须绿；15K-J/`af48d21` 历史红点具名披露，不伪称全范围绿。 |
