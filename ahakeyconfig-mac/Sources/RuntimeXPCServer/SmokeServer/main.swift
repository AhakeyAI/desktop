import AhaKeyConfigShared
import Foundation
import RuntimeXPCServer

// WBS 5.2 真实双进程 smoke 的 server helper（仅测试用途）。
// 用法：RuntimeXPCSmokeServer <serviceName> <teamID> <allowedSigningID> <resultPath>
// 行为：以生产 libxpc 路径启动 listener；每次业务 endpoint 被调用都会把计数写入
// resultPath（JSON：{"businessCalls":N}）；收到 SIGTERM/SIGINT 时落盘并退出 0。

struct SmokeResult: Codable {
    var businessCalls: Int
}

final class SmokeState: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let resultURL: URL

    init(resultURL: URL) {
        self.resultURL = resultURL
        persist()
    }

    func increment() {
        lock.lock()
        calls += 1
        lock.unlock()
        persist()
    }

    func persist() {
        lock.lock()
        let snapshot = SmokeResult(businessCalls: calls)
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: resultURL, options: .atomic)
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    FileHandle.standardError.write(Data("usage: RuntimeXPCSmokeServer <serviceName> <teamID> <allowedSigningID> <resultPath>\n".utf8))
    exit(64)
}
let serviceName = arguments[1]
let teamID = arguments[2]
let allowedSigningID = arguments[3]
let resultURL = URL(fileURLWithPath: arguments[4])

let state = SmokeState(resultURL: resultURL)
let serverHandshake = AhaKeyRuntimeXPCServerHandshake(
    runtimeVersion: .development,
    interfaceVersion: .current,
    supportedConfigurationSchemaVersions: [1],
    capabilities: [.snapshot, .eventReplay, .configuration, .diagnostics, .firmwareUpgrade, .policy]
)
let peerPolicy = AhaKeyRuntimeXPCPeerPolicy(
    expectedUserID: getuid(),
    expectedTeamIdentifier: teamID,
    allowedSigningIdentifiers: [allowedSigningID]
)

let server: AhaKeyRuntimeXPCLibXPCServer
do {
    server = try AhaKeyRuntimeXPCLibXPCServer(
        serviceName: serviceName,
        peerPolicy: peerPolicy
    ) {
        AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: serverHandshake) { _ in
            state.increment()
            return .policyUpdated
        }
    }
} catch {
    FileHandle.standardError.write(Data("server init failed: \(error)\n".utf8))
    exit(65)
}

server.start()
print("READY \(serviceName)")
fflush(stdout)

// 退出路径可靠清理：信号到达时落盘并退出；listener 随进程退出自动释放。
// 必须先 SIG_IGN 默认处置，DispatchSource 才能接管。
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
for sig in [SIGTERM, SIGINT] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        state.persist()
        exit(0)
    }
    source.resume()
}

dispatchMain()
