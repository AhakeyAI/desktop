import Foundation

// 插件生命周期握手 —— 借鉴 LSP 的 initialize/initialized/shutdown 流程。
//
// 时序：
//   1. 宿主 spawn 子进程 → `client.start()`
//   2. 宿主 → 插件:  call  `plugin/initialize`  (params: { host, hostMethods })
//   3. 插件 → 宿主:  result `{ name, version, methods }`（声明自己能处理哪些 method）
//   4. 宿主 → 插件:  notify `plugin/initialized`（可选；告诉插件可以开始干活）
//   5. ... 正常 RPC ...
//   6. 宿主 → 插件:  call  `plugin/shutdown`（等插件清理）
//   7. 宿主 → 插件:  notify `plugin/exit`
//   8. 宿主关闭 stdin → 子进程退出

public struct PluginInitializeParams: Codable, Sendable {
    public let host: HostAppInfo
    public let hostMethods: [String]

    public init(host: HostAppInfo, hostMethods: [String]) {
        self.host = host
        self.hostMethods = hostMethods
    }
}

public struct PluginInitializeResult: Codable, Sendable {
    /// 插件自称的 id / name / version；只用来记日志、设置面板展示。
    /// 宿主信任的是 manifest 里的那一份。
    public let name: String?
    public let version: String?

    /// 插件声明它能处理的 method 列表。宿主可以据此提前拒绝乱发 method。
    public let methods: [String]?

    public init(name: String? = nil, version: String? = nil, methods: [String]? = nil) {
        self.name = name
        self.version = version
        self.methods = methods
    }
}

public extension PluginClient {
    /// 完成 `plugin/initialize` 握手。失败时把错误透出（超时 → `PluginClientError.timeout`）。
    @discardableResult
    func initialize(
        host: HostAppInfo,
        hostMethods: [String],
        timeout: TimeInterval = 5
    ) async throws -> PluginInitializeResult {
        let params = try JSONValue.encode(
            PluginInitializeParams(host: host, hostMethods: hostMethods)
        )
        let result = try await call("plugin/initialize", params: params, timeout: timeout)
        return try result.decode(PluginInitializeResult.self)
    }

    /// 通知插件「初始化完成，可以开干」。失败被吞掉（notification 没有响应）。
    func sendInitialized() throws {
        try notify("plugin/initialized")
    }

    /// 请求插件清理并准备退出。失败/超时不抛，调用方接着 `stop()` 即可。
    func shutdown(timeout: TimeInterval = 3) async {
        _ = try? await call("plugin/shutdown", timeout: timeout)
        try? notify("plugin/exit")
    }
}
