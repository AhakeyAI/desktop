import Foundation

// 在 PluginClient 之上包一层「宿主能力」：注册一组 `host/*` JSON-RPC method，
// 让插件能调用宿主提供的服务。
//
// 当前最小三件套：
//   - host/getInfo          → 返回宿主 app 元信息（bundleID / version / build / platform）
//   - host/log              → 插件把日志打到宿主 stderr
//   - host/getSwitchState   → 通过 /tmp/ahakey.sock 问 daemon 拨杆状态（agent 没跑则返回 null）
//
// 后续要加的（如 host/showNotification、host/openURL、host/storage/*）按相同方式接到
// `registerDefaultHandlers` 即可。增加新方法时记得在 manifest 的权限白名单里同步声明。

public final class PluginHost: @unchecked Sendable {
    public let client: PluginClient
    public let appInfo: HostAppInfo

    /// 该插件被允许调用的 `host/*` 方法集合；`nil` 表示不限制（仅用于 demo / 第一方）。
    public let permissions: Set<String>?

    public init(
        client: PluginClient,
        appInfo: HostAppInfo = .current(),
        permissions: Set<String>? = nil
    ) {
        self.client = client
        self.appInfo = appInfo
        self.permissions = permissions
    }

    /// 宿主当前 expose 的全部 `host/*` 方法名 —— 用于 `plugin/initialize` 时告诉插件。
    public static let availableHostMethods: [String] = [
        "host/getInfo",
        "host/log",
        "host/getSwitchState",
    ]

    /// 注册默认 `host/*` 方法集。请在 `client.start()` 之前调用。
    public func registerDefaultHandlers() async {
        let appInfo = self.appInfo

        await register("host/getInfo") { _ in
            try JSONValue.encode(appInfo)
        }

        await register("host/log") { params in
            HostLog.write(params: params)
            return .null
        }

        await register("host/getSwitchState") { _ in
            let state = HostAgentBridge.readSwitchState()
            return .object([
                "switchState": state.map { JSONValue.int($0) } ?? .null,
                "agentReachable": .bool(state != nil),
            ])
        }
    }

    /// 包一层权限检查后注册。不在 `permissions` 里的 method 会被 -32601 直接拒掉。
    private func register(
        _ method: String,
        _ handler: @escaping PluginClient.RequestHandler
    ) async {
        let permissions = self.permissions
        await client.setRequestHandler(method) { params in
            if let permissions, !permissions.contains(method) {
                throw JSONRPCError(
                    code: JSONRPCError.methodNotFound,
                    message: "Method \(method) not in plugin permissions",
                    data: nil
                )
            }
            return try await handler(params)
        }
    }
}

// MARK: - host/getInfo

public struct HostAppInfo: Codable, Sendable {
    public let bundleID: String
    public let version: String
    public let build: String
    public let platform: String

    public init(bundleID: String, version: String, build: String, platform: String = "macos") {
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.platform = platform
    }

    /// 从 `Bundle.main` 读；当宿主不是 app bundle（例如本 Plugin demo executable）时给保底值。
    public static func current() -> HostAppInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return .init(
            bundleID: Bundle.main.bundleIdentifier ?? "dev.ahakey.unknown",
            version: info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            build: info["CFBundleVersion"] as? String ?? "0"
        )
    }
}

// MARK: - host/log

enum HostLog {
    /// 兼容两种 params 形态：
    ///   - `{ "level": "info", "message": "..." }`
    ///   - `"plain string message"`
    static func write(params: JSONValue?) {
        var level = "info"
        var message = ""
        if case .object(let o)? = params {
            if case .string(let s)? = o["level"] { level = s }
            if case .string(let s)? = o["message"] { message = s }
        } else if case .string(let s)? = params {
            message = s
        }
        FileHandle.standardError.write(
            Data("[plugin:\(level)] \(message)\n".utf8)
        )
    }
}

// MARK: - host/getSwitchState

/// 与 `Agent/HookClient.swift` 走同一套 `/tmp/ahakey.sock` 协议
/// （`{"cmd":"permission","value":1}` → `{"switchState": Int, ...}`）。
/// agent 没跑或 BLE 没连上时返回 nil。
///
/// 没把 socket 协议抽成共用 util，是因为 Agent target 与 AhaKeyPluginKit 暂不互相依赖；
/// 后续若多处都要用，再抽 `AhaKeyAgentBridge` library。
enum HostAgentBridge {
    static let socketPath = "/tmp/ahakey.sock"
    static let timeout: Double = 2.0

    static func readSwitchState() -> Int? {
        let req: [String: Any] = ["cmd": "permission", "value": 1]
        guard let reply = sendJson(req) else { return nil }
        if let i = reply["switchState"] as? Int { return i }
        if let n = reply["switchState"] as? NSNumber { return n.intValue }
        return nil
    }

    private static func sendJson(_ dict: [String: Any]) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var tv = timeval(tv_sec: __darwin_time_t(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let dst = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                _ = strcpy(dst, src)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard connected == 0 else { return nil }

        guard var payload = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        payload.append(0x0A)
        let wrote = payload.withUnsafeBytes { p -> Int in
            guard let base = p.baseAddress else { return -1 }
            return write(fd, base, p.count)
        }
        guard wrote >= 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(buf[0 ..< Int(n)]))) as? [String: Any]
    }
}
