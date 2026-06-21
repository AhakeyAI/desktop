import Foundation

/// 一个 JSON-RPC 2.0 over stdio 客户端。
///
/// - 启动子进程（插件 host 端 = 我们；子进程 = 插件本体）。
/// - 帧格式：**newline-delimited JSON**（每条消息一行 UTF-8 + `\n`）。
///   这是 stdio 通讯里最常见的选择；如果未来要换成 LSP 的 `Content-Length` 头，
///   只需替换 `sendFramed(_:)` 与 reader 里的拆帧逻辑。
/// - 子进程的 `stderr` 透传给上层（默认打到本进程 stderr，可换 `onStderr`）。
///
/// 用法：
/// ```swift
/// let client = PluginClient(
///     executable: URL(fileURLWithPath: "/usr/bin/env"),
///     arguments: ["node", "my-plugin.js"]
/// )
/// try client.start()
/// let result = try await client.call("add", params: .array([.int(1), .int(2)]))
/// // result == .int(3)
/// client.stop()
/// ```
public actor PluginClient {
    // MARK: - 配置

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let workingDirectory: URL?

    /// 单次 `call` 等待响应的默认超时。`notify` 不受此影响。
    public var defaultCallTimeout: TimeInterval = 30

    /// 子进程 stderr 回调，nil 表示透传到本进程 stderr。
    public var onStderr: (@Sendable (String) -> Void)?

    // MARK: - 进程 / 管道

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var started = false

    // MARK: - 协议状态

    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]

    /// 服务端 → 客户端的 notification 处理器（method → 处理闭包）。
    public typealias NotificationHandler = @Sendable (JSONValue?) -> Void
    private var notificationHandlers: [String: NotificationHandler] = [:]

    /// 服务端 → 客户端的 request 处理器（method → 返回 result 或抛 JSONRPCError）。
    /// JSON-RPC 是对等协议，子进程也可以反向调用我们。
    public typealias RequestHandler = @Sendable (JSONValue?) async throws -> JSONValue
    private var requestHandlers: [String: RequestHandler] = [:]

    // MARK: - 初始化

    public init(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    // MARK: - 启动 / 停止

    public func start() throws {
        guard !started else { return }
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // 子进程退出时，唤醒所有 pending。
        process.terminationHandler = { [weak self] proc in
            Task { await self?.handleProcessTermination(status: proc.terminationStatus) }
        }

        try process.run()
        started = true
        startReader()
        startStderrReader()
    }

    /// 优雅停止：关闭 stdin，等子进程自然退出；若想强杀用 `terminate()`。
    public func stop() {
        guard started else { return }
        try? stdinPipe.fileHandleForWriting.close()
    }

    public func terminate() {
        guard started else { return }
        process.terminate()
    }

    // MARK: - 注册回调

    public func setNotificationHandler(_ method: String, _ handler: @escaping NotificationHandler) {
        notificationHandlers[method] = handler
    }

    public func setRequestHandler(_ method: String, _ handler: @escaping RequestHandler) {
        requestHandlers[method] = handler
    }

    // MARK: - 发送：call / notify

    /// 发起 JSON-RPC 调用，等待响应。
    @discardableResult
    public func call(
        _ method: String,
        params: JSONValue? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> JSONValue {
        guard started, process.isRunning else { throw PluginClientError.notRunning }

        let id = nextID
        nextID += 1
        let request = JSONRPCRequest(method: method, params: params, id: .int(id))

        // 先注册 continuation，再发数据，避免响应早于注册。
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONValue, Error>) in
                pending[id] = cont
                do {
                    try sendFramed(request)
                } catch {
                    pending.removeValue(forKey: id)
                    cont.resume(throwing: error)
                    return
                }
                armTimeout(id: id, after: timeout ?? defaultCallTimeout)
            }
        } onCancel: {
            Task { await self.failPending(id: id, with: CancellationError()) }
        }
    }

    /// 发送 Notification（无 id，不等响应）。
    public func notify(_ method: String, params: JSONValue? = nil) throws {
        guard started, process.isRunning else { throw PluginClientError.notRunning }
        let request = JSONRPCRequest(method: method, params: params, id: nil)
        try sendFramed(request)
    }

    // MARK: - 帧编码

    private func sendFramed(_ request: JSONRPCRequest) throws {
        var data = try JSONEncoder().encode(request)
        data.append(0x0A) // '\n'
        if ProcessInfo.processInfo.environment["AHAKEY_PLUGIN_DEBUG"] != nil,
           let s = String(data: data, encoding: .utf8) {
            FileHandle.standardError.write(Data("[client→plugin] \(s)".utf8))
        }
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    // MARK: - Reader（stdout）

    // 之前用 `handle.bytes.lines` 在 daemon-thread 写 stdout 的场景下会延迟数秒才触发，
    // 改用 `readabilityHandler` 走 dispatch IO，事件驱动、即时。
    private var stdoutBuffer = Data()

    private func startReader() {
        let handle = stdoutPipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self else { return }
            if data.isEmpty {
                // EOF —— 子进程关了 stdout。
                h.readabilityHandler = nil
                Task { await self.handleProcessTermination(status: nil) }
                return
            }
            Task { await self.appendStdout(data) }
        }
    }

    private func appendStdout(_ data: Data) async {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex ..< nl)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex ... nl)
            if let line = String(data: lineData, encoding: .utf8) {
                await handleIncoming(line: line)
            }
        }
    }

    private func startStderrReader() {
        let handle = stderrPipe.fileHandleForReading
        let onStderr = self.onStderr
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                return
            }
            if let onStderr, let s = String(data: data, encoding: .utf8) {
                // 按行回调；保留尾部不完整行（罕见）。
                for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
                    if !line.isEmpty { onStderr(String(line)) }
                }
            } else {
                FileHandle.standardError.write(data)
            }
        }
    }

    // MARK: - 入站派发

    private func handleIncoming(line: String) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        if ProcessInfo.processInfo.environment["AHAKEY_PLUGIN_DEBUG"] != nil {
            FileHandle.standardError.write(Data("[client←plugin] \(trimmed)\n".utf8))
        }

        // 一条消息可能是：Response（含 id + result/error）、Request（含 id + method）、
        // 或 Notification（含 method 但无 id）。先看有没有 `method` 字段。
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           raw["method"] is String {
            await dispatchInbound(data: data, raw: raw)
            return
        }

        // 当作 Response 解。
        do {
            let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
            dispatch(response: resp)
        } catch {
            // 实在解不出来：丢到 stderr 便于排查。
            FileHandle.standardError.write(
                Data("[PluginClient] unrecognized frame: \(trimmed)\n".utf8)
            )
        }
    }

    private func dispatch(response: JSONRPCResponse) {
        guard case .int(let i)? = response.id else {
            // 我们发出去的 id 全是 int；其他 id 形式直接丢弃。
            return
        }
        guard let cont = pending.removeValue(forKey: i) else { return }
        if let err = response.error {
            cont.resume(throwing: err)
        } else {
            cont.resume(returning: response.result ?? .null)
        }
    }

    private func dispatchInbound(data: Data, raw: [String: Any]) async {
        guard let method = raw["method"] as? String else { return }
        let params: JSONValue? = {
            guard raw["params"] != nil else { return nil }
            // 用 JSONValue 重新解一遍 params 字段。
            struct Wrapper: Decodable { let params: JSONValue? }
            return (try? JSONDecoder().decode(Wrapper.self, from: data))?.params
        }()

        if raw["id"] == nil {
            // Notification
            notificationHandlers[method]?(params)
            return
        }

        // 入站 Request：要回 Response。
        let id: JSONRPCID
        do {
            struct Wrapper: Decodable { let id: JSONRPCID }
            id = try JSONDecoder().decode(Wrapper.self, from: data).id
        } catch {
            return
        }

        if let handler = requestHandlers[method] {
            do {
                let result = try await handler(params)
                try sendResult(id: id, result: result)
            } catch let err as JSONRPCError {
                try? sendError(id: id, error: err)
            } catch {
                try? sendError(id: id, error: JSONRPCError(
                    code: JSONRPCError.internalError,
                    message: "\(error)",
                    data: nil
                ))
            }
        } else {
            try? sendError(id: id, error: JSONRPCError(
                code: JSONRPCError.methodNotFound,
                message: "Method not found: \(method)",
                data: nil
            ))
        }
    }

    private struct OutboundResponse: Encodable {
        let jsonrpc: String = JSONRPC.version
        let id: JSONRPCID
        let result: JSONValue?
        let error: JSONRPCError?
    }

    private func sendResult(id: JSONRPCID, result: JSONValue) throws {
        let resp = OutboundResponse(id: id, result: result, error: nil)
        var data = try JSONEncoder().encode(resp)
        data.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func sendError(id: JSONRPCID, error: JSONRPCError) throws {
        let resp = OutboundResponse(id: id, result: nil, error: error)
        var data = try JSONEncoder().encode(resp)
        data.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    // MARK: - 超时 / 取消 / 进程终止

    private func armTimeout(id: Int, after seconds: TimeInterval) {
        guard seconds > 0 else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            failPending(id: id, with: PluginClientError.timeout)
        }
    }

    private func failPending(id: Int, with error: Error) {
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(throwing: error)
    }

    private func handleProcessTermination(status: Int32?) {
        guard started else { return }
        started = false
        let err: Error = status.map { PluginClientError.processTerminated($0) }
            ?? PluginClientError.notRunning
        let pendingSnapshot = pending
        pending.removeAll()
        for (_, cont) in pendingSnapshot {
            cont.resume(throwing: err)
        }
    }
}

