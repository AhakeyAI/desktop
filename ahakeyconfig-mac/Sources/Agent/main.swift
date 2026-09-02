import Foundation
import AhaKeyConfigShared

// ahakeyconfig-agent
//
// 两种运行模式（由首个参数决定）：
//   1. Daemon（无参数 / 只传 --socket）：常驻 LaunchAgent，维持 BLE 连接 + 监听 Unix socket
//        ahakeyconfig-agent [--socket ~/Library/Application Support/AhaKeyConfig/ahakey.sock]
//   2. Hook 子命令（首个参数为 hook）：Claude Code / Cursor / Codex / Kimi Code CLI 会 exec 本进程
//        ahakeyconfig-agent hook <EventName>
//      内部通过 Unix socket 联系常驻 daemon，并按需向 stdout 输出 Claude 决策 JSON。

let args = CommandLine.arguments

if args.count >= 3, args[1] == "hook" {
    let event = args[2]
    exit(HookClient.run(event: event))
}

// Daemon 模式。Hook 子进程已在 HookClient 忽略 SIGPIPE；常驻进程必须同样忽略，
// 否则 legacy ahakey.sock 对已关闭客户端的 write() 会直接终止 Runtime。
signal(SIGPIPE, SIG_IGN)

let socketPath: String
if let idx = args.firstIndex(of: "--socket"), idx + 1 < args.count {
    socketPath = args[idx + 1]
} else {
    socketPath = AhaKeyPaths.agentSocketPath
}

let agent = AhaKeyAgent(socketPath: socketPath)
agent.onLog = { msg in
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] \(msg)")
}
agent.startSocketListener()
do {
    try agent.startHookServer()
} catch {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] Hook server 启动失败: \(error)")
}
do {
    try agent.startXPCServer()
} catch {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] XPC server 启动失败: \(error)")
    print("[\(ts)] 说明：XPC service 'lab.jawa.ahakeyconfig.runtime' 需要 launchd MachServices 登记。")
    print("[\(ts)] 请将以下 plist 放入 ~/Library/LaunchAgents/ 并执行 launchctl load：")
    print("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>lab.jawa.ahakeyconfig.agent</string>
        <key>MachServices</key>
        <dict>
            <key>lab.jawa.ahakeyconfig.runtime</key>
            <true/>
        </dict>
        <key>ProgramArguments</key>
        <array>
            <string>/Applications/AhaKeyConfig.app/Contents/MacOS/ahakeyconfig-agent</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
    </dict>
    </plist>
    """)
    print("[\(ts)] 缺少 launchd 登记时 Studio 无法通过 XPC 下发配置；Agent 仍提供 BLE/Hook 服务。")
}

// Graceful cleanup on SIGINT/SIGTERM. SIGKILL cannot be caught; stale state is
// cleaned up the next time either process starts.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigintSource.setEventHandler {
    agent.shutdown()
    exit(0)
}
sigtermSource.setEventHandler {
    agent.shutdown()
    exit(0)
}
sigintSource.resume()
sigtermSource.resume()

// 保持运行
RunLoop.main.run()
