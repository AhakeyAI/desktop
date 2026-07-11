import AppKit
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
        "host/openUrl",
        "host/openPath",
        "host/pasteText",
        "host/registerGlobalHotkey",
        "host/unregisterGlobalHotkey",
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

        await register("host/openUrl") { params in
            let url = try HostActionParams.requiredString(params, key: "url", method: "host/openUrl")
            guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") else {
                throw JSONRPCError(code: JSONRPCError.invalidParams, message: "host/openUrl expects an http(s) URL")
            }
            let opened = await MainActor.run {
                NSWorkspace.shared.open(parsed)
            }
            return .object(["opened": .bool(opened)])
        }

        await register("host/openPath") { params in
            let path = try HostActionParams.requiredString(params, key: "path", method: "host/openPath")
            let opened = await MainActor.run {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
            return .object(["opened": .bool(opened)])
        }

        await register("host/pasteText") { params in
            let text = try HostActionParams.requiredString(params, key: "text", method: "host/pasteText")
            await MainActor.run {
                HostTextInjector.paste(text)
            }
            return .object(["pasted": .bool(true)])
        }

        await register("host/registerGlobalHotkey") { [weak self] params in
            guard let self else {
                throw JSONRPCError(code: JSONRPCError.internalError, message: "PluginHost is unavailable")
            }
            let hotkey = try HostActionParams.requiredString(params, key: "hotkey", method: "host/registerGlobalHotkey")
            let callbackMethod = try HostActionParams.requiredString(params, key: "callbackMethod", method: "host/registerGlobalHotkey")
            let token = HostHotkeyRegistry.shared.register(
                hotkey: hotkey,
                callbackMethod: callbackMethod,
                client: self.client
            )
            return .object(["token": .string(token)])
        }

        await register("host/unregisterGlobalHotkey") { params in
            let token = try HostActionParams.requiredString(params, key: "token", method: "host/unregisterGlobalHotkey")
            HostHotkeyRegistry.shared.unregister(token: token)
            return .object(["unregistered": .bool(true)])
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

// MARK: - host action params

enum HostActionParams {
    static func requiredString(_ params: JSONValue?, key: String, method: String) throws -> String {
        guard case .object(let object)? = params,
              case .string(let value)? = object[key],
              !value.isEmpty else {
            throw JSONRPCError(
                code: JSONRPCError.invalidParams,
                message: "\(method) expects string parameter '\(key)'",
                data: nil
            )
        }
        return value
    }
}

// MARK: - host/pasteText

enum HostTextInjector {
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

// MARK: - host/registerGlobalHotkey

final class HostHotkeyRegistry: @unchecked Sendable {
    static let shared = HostHotkeyRegistry()

    private struct Registration {
        let token: String
        let hotkey: ParsedHotkey
        let callbackMethod: String
        let client: PluginClient
    }

    private let lock = NSLock()
    private var registrations: [String: Registration] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private init() {}

    func register(hotkey: String, callbackMethod: String, client: PluginClient) -> String {
        let parsed = ParsedHotkey.parse(hotkey)
        let token = UUID().uuidString
        let registration = Registration(
            token: token,
            hotkey: parsed,
            callbackMethod: callbackMethod,
            client: client
        )
        lock.lock()
        registrations[token] = registration
        let shouldInstall = localMonitor == nil && globalMonitor == nil
        lock.unlock()

        if shouldInstall {
            installMonitors()
        }
        return token
    }

    func unregister(token: String) {
        lock.lock()
        registrations.removeValue(forKey: token)
        let shouldRemove = registrations.isEmpty
        lock.unlock()

        if shouldRemove {
            removeMonitors()
        }
    }

    private func installMonitors() {
        DispatchQueue.main.async {
            if self.localMonitor == nil {
                self.localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handle(event: event)
                    return event
                }
            }
            if self.globalMonitor == nil {
                self.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handle(event: event)
                }
            }
        }
    }

    private func removeMonitors() {
        DispatchQueue.main.async {
            if let localMonitor = self.localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            if let globalMonitor = self.globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
        }
    }

    private func handle(event: NSEvent) {
        lock.lock()
        let matches = registrations.values.filter { $0.hotkey.matches(event: event) }
        lock.unlock()

        for registration in matches {
            let params: JSONValue = .object([
                "token": .string(registration.token),
                "hotkey": .string(registration.hotkey.display),
            ])
            Task {
                _ = try? await registration.client.call(registration.callbackMethod, params: params)
            }
        }
    }
}

struct ParsedHotkey {
    let display: String
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    static func parse(_ hotkey: String) -> ParsedHotkey {
        let parts = hotkey
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var modifiers: NSEvent.ModifierFlags = []
        var key: String?
        for part in parts {
            switch part {
            case "cmd", "command", "meta": modifiers.insert(.command)
            case "ctrl", "control": modifiers.insert(.control)
            case "alt", "option": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default: key = part
            }
        }
        guard let key, let keyCode = Self.keyCode(for: key) else {
            return ParsedHotkey(display: hotkey, keyCode: 11, modifiers: [.control, .option, .shift])
        }
        return ParsedHotkey(display: hotkey, keyCode: keyCode, modifiers: modifiers)
    }

    func matches(event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return event.keyCode == keyCode
            && event.modifierFlags.intersection(relevant) == modifiers.intersection(relevant)
    }

    private static func keyCode(for key: String) -> UInt16? {
        [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
            "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50,
        ][key]
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
