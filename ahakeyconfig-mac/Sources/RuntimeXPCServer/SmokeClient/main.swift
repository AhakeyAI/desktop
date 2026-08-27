import AhaKeyConfigShared
import Foundation

// 正向路径必须调用与 Studio 相同的生产 transport（AhaKeyStudioRuntimeXPCTransport /
// AhaKeyRuntimeXPCLibXPCClient）。禁止再保留一份独立 libxpc send 循环。
// 用法：RuntimeXPCSmokeClient <serviceName> <mode: positive|negative>
// positive：握手 + snapshot 都应成功，退出码 0。
// negative（ad-hoc 签名）：应在业务 payload 前被 libxpc 拒绝，退出码 3。
// 任何意外错误退出码 2；10 秒 watchdog 兜底。

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: RuntimeXPCSmokeClient <serviceName> <positive|negative>\n".utf8))
    exit(64)
}
let serviceName = arguments[1]
let mode = arguments[2]

DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
    FileHandle.standardError.write(Data("RESULT: timeout\n".utf8))
    exit(2)
}

let transport = AhaKeyStudioRuntimeXPCTransport(machServiceName: serviceName, timeout: 5)
let done = DispatchSemaphore(value: 0)

Task {
    defer { done.signal() }
    do {
        let handshake = try await transport.exchange(
            .handshake(.init(interfaceVersion: .current, clientBuildID: "runtime-xpc-smoke-client"))
        )
        guard case .handshakeAccepted(let serverHandshake) = handshake else {
            FileHandle.standardError.write(Data("RESULT: bad-handshake-response\n".utf8))
            exit(2)
        }
        let capabilityNames = serverHandshake.capabilities.map { $0.rawValue }.sorted()
        print("HANDSHAKE: runtime=\(serverHandshake.runtimeVersion) interface=\(serverHandshake.interfaceVersion) schema=\(serverHandshake.supportedConfigurationSchemaVersions.sorted()) capabilities=\(capabilityNames)")
        if mode == "positive" {
            _ = try await transport.exchange(.snapshot)
            print("RESULT: ok")
            exit(0)
        }
        print("RESULT: negative-not-rejected")
        exit(4)
    } catch AhaKeyRuntimeXPCTransportError.connectionInvalid {
        print("RESULT: rejected")
        exit(3)
    } catch is CancellationError {
        FileHandle.standardError.write(Data("RESULT: cancelled\n".utf8))
        exit(2)
    } catch {
        FileHandle.standardError.write(Data("RESULT: unexpected \(error)\n".utf8))
        exit(2)
    }
}

done.wait()
