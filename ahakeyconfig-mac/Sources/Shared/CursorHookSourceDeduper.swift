import Foundation

public enum CursorHookRoute: Equatable, Sendable {
    case queryRuntime
    case noOp
    case passthrough
}

/// 把 Cursor 原生入口、旧残留入口和 Claude 映射来源收敛为单一决策链。
public enum CursorHookSourceDeduper {
    public static func route(
        event: String,
        environment: [String: String]
    ) -> CursorHookRoute {
        switch event {
        case "preToolUse":
            return .queryRuntime
        case "beforeShellExecution", "beforeMCPExecution":
            return .noOp
        case "PreToolUse":
            let cursorVersion = environment["CURSOR_VERSION"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cursorVersion?.isEmpty == false ? .noOp : .passthrough
        default:
            return .passthrough
        }
    }
}
