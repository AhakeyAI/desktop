import AhaKeyConfigShared
import CLibXPC
import Foundation

// WBS 5.2 真实双进程 smoke 的 client helper（仅测试用途）。
// 用法：RuntimeXPCSmokeClient <serviceName> <mode: positive|negative>
// positive：握手 + 业务请求都应成功，退出码 0。
// negative（ad-hoc 签名）：握手消息应在 payload 处理前被 libxpc 拒绝，退出码 3。
// 任何意外错误退出码 2；10 秒 watchdog 兜底。

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: RuntimeXPCSmokeClient <serviceName> <positive|negative>\n".utf8))
    exit(64)
}
let serviceName = arguments[1]
let mode = arguments[2]

// watchdog：任何挂起都不能让 smoke 无限等待。
DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
    FileHandle.standardError.write(Data("RESULT: timeout\n".utf8))
    exit(2)
}

let connection = serviceName.withCString { cName in
    xpc_connection_create_mach_service(cName, DispatchQueue.global(), 0)
}
final class ReplyBox: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var replies: [xpc_object_t] = []
    func push(_ object: xpc_object_t) {
        lock.lock()
        replies.append(object)
        lock.unlock()
        semaphore.signal()
    }
    func pop(timeout: DispatchTime) -> xpc_object_t? {
        guard semaphore.wait(timeout: timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}
let box = ReplyBox()
xpc_connection_set_event_handler(connection) { event in
    box.push(event)
}
xpc_connection_resume(connection)

func sendAndWait(_ request: AhaKeyRuntimeXPCRequest, label: String) -> xpc_object_t? {
    guard let payload = try? JSONEncoder().encode(request) else {
        FileHandle.standardError.write(Data("encode failed\n".utf8))
        exit(2)
    }
    let message = xpc_dictionary_create(nil, nil, 0)
    payload.withUnsafeBytes { buffer in
        xpc_dictionary_set_data(message, "payload", buffer.baseAddress!, buffer.count)
    }
    xpc_connection_send_message(connection, message)
    return box.pop(timeout: .now() + 5)
}

let handshake = AhaKeyRuntimeXPCRequest.handshake(
    .init(interfaceVersion: .current, clientBuildID: "runtime-xpc-smoke-client")
)
guard let handshakeReply = sendAndWait(handshake, label: "handshake") else {
    FileHandle.standardError.write(Data("RESULT: no-reply\n".utf8))
    exit(2)
}

if xpc_get_type(handshakeReply) == XPC_TYPE_ERROR {
    // libxpc 在 payload 处理前拒绝了消息（签名/Team ID 不匹配）。
    print("RESULT: rejected")
    exit(3)
}
guard xpc_get_type(handshakeReply) == XPC_TYPE_DICTIONARY else {
    FileHandle.standardError.write(Data("RESULT: unexpected-type\n".utf8))
    exit(2)
}
if xpc_dictionary_get_string(handshakeReply, "error") != nil {
    FileHandle.standardError.write(Data("RESULT: endpoint-error\n".utf8))
    exit(2)
}
var payloadLength = 0
guard let payloadPointer = xpc_dictionary_get_data(handshakeReply, "payload", &payloadLength) else {
    FileHandle.standardError.write(Data("RESULT: no-payload\n".utf8))
    exit(2)
}
let responseData = Data(bytes: payloadPointer, count: payloadLength)
guard let response = try? JSONDecoder().decode(AhaKeyRuntimeXPCResponse.self, from: responseData),
      case .handshakeAccepted(let serverHandshake) = response
else {
    FileHandle.standardError.write(Data("RESULT: bad-handshake-response\n".utf8))
    exit(2)
}

let capabilityNames = serverHandshake.capabilities.map { $0.rawValue }.sorted()
print("HANDSHAKE: runtime=\(serverHandshake.runtimeVersion) interface=\(serverHandshake.interfaceVersion) schema=\(serverHandshake.supportedConfigurationSchemaVersions.sorted()) capabilities=\(capabilityNames)")

// 正向模式再发一个业务请求，确认握手后白名单路径可用。
if mode == "positive" {
    guard let businessReply = sendAndWait(.snapshot, label: "snapshot"),
          xpc_get_type(businessReply) == XPC_TYPE_DICTIONARY,
          xpc_dictionary_get_string(businessReply, "error") == nil,
          xpc_dictionary_get_data(businessReply, "payload", nil) != nil
    else {
        FileHandle.standardError.write(Data("RESULT: business-failed\n".utf8))
        exit(2)
    }
    print("RESULT: ok")
    exit(0)
}

// negative 模式走到这里说明 ad-hoc 客户端竟完成了握手——这是失败。
print("RESULT: negative-not-rejected")
exit(4)
