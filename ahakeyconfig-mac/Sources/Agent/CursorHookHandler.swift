import Foundation
import AhaKeyConfigShared

enum CursorHookHandler {
    static func handleToolPermission(hookEvent: String) {
        let stdinData = HookSupport.readAllStdinSilently()
        let startedAt = ProcessInfo.processInfo.systemUptime
        let queryClient = AhaKeyRuntimeCursorHookQueryClient(
            socketURL: AhaKeyPaths.runtimeHookSocketURL,
            hookBuildID: HookSupport.hookBuildIdentifier,
            timeout: HookSupport.cursorRuntimeQueryTimeout
        )
        let result = CursorHookDecisionService(queryPort: queryClient).decide(requestID: UUID())

        // 只有 fresh automatic 显式 allow。manual / offline / timeout 保持 stdout
        // 为空并成功退出，让 Cursor 原生 Run Mode / 批准流继续决定。
        if let standardOutput = result.standardOutput {
            FileHandle.standardOutput.write(Data((standardOutput + "\n").utf8))
        }

        let protocolVersion = AhaKeyRuntimeHookProtocolVersion.current
        let healthLogURL = AhaKeyPaths.applicationSupportDirectory
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("cursor-hook-health.jsonl")
        try? CursorHookHealthStore(fileURL: healthLogURL).record(
            eventCategory: .toolPermission,
            decision: result.decision,
            latency: ProcessInfo.processInfo.systemUptime - startedAt,
            failure: result.queryFailure,
            hookVersion: HookSupport.hookBuildIdentifier,
            runtimeProtocolVersion: "\(protocolVersion.major).\(protocolVersion.minor)"
        )

        // stdin 已被消费；健康日志 API 不接受 prompt、命令、cwd、完整路径或环境变量。
        _ = stdinData
    }
}
