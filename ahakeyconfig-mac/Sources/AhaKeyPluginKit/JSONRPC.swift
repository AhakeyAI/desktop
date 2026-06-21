import Foundation

// JSON-RPC 2.0 协议类型（https://www.jsonrpc.org/specification）。
//
// 设计取舍：
// - params / result 是任意 JSON，用本文件里的 `JSONValue` 表达，避免引入第三方 AnyCodable。
// - id 允许 int / string / null（按规范）；本客户端只主动使用 int，但收到 string/null 也能解。
// - 不区分 batch 调用（暂不需要）。要支持时再加 `[JSONRPCResponse]` 解码分支。

public enum JSONRPC {
    public static let version = "2.0"
}

// MARK: - JSONValue

/// 任意 JSON 值。
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        // Int 先于 Double：纯整数解出来是 .int。
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public extension JSONValue {
    /// 把任意 Encodable 转成 JSONValue（走一遍 JSONEncoder/Decoder）。
    static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// 把 JSONValue 解成具体类型。
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - ID

/// JSON-RPC id：规范允许 Number / String / Null。
public enum JSONRPCID: Hashable, Sendable {
    case int(Int)
    case string(String)
    case null
}

extension JSONRPCID: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "JSON-RPC id must be number, string, or null"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Request / Notification

/// 出站请求；`id == nil` 代表 Notification（按规范连 `id` 字段都不编码）。
public struct JSONRPCRequest: Encodable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: JSONValue?
    public let id: JSONRPCID?

    public init(method: String, params: JSONValue?, id: JSONRPCID?) {
        self.jsonrpc = JSONRPC.version
        self.method = method
        self.params = params
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params, id
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jsonrpc, forKey: .jsonrpc)
        try c.encode(method, forKey: .method)
        if let params { try c.encode(params, forKey: .params) }
        if let id { try c.encode(id, forKey: .id) }
    }
}

// MARK: - Response

public struct JSONRPCResponse: Decodable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: JSONValue?
    public let error: JSONRPCError?
}

public struct JSONRPCError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public extension JSONRPCError {
    // 规范保留错误码。-32000..-32099 留给实现自定义。
    static let parseError      = -32700
    static let invalidRequest  = -32600
    static let methodNotFound  = -32601
    static let invalidParams   = -32602
    static let internalError   = -32603
}

// MARK: - 客户端侧错误

public enum PluginClientError: Error, Sendable {
    /// 子进程未启动 / 已退出。
    case notRunning
    /// 子进程意外退出，附终止码。
    case processTerminated(Int32)
    /// 响应 id 与所有 pending 都对不上。
    case unknownResponseID(JSONRPCID?)
    /// 单次 call 等待超时。
    case timeout
    /// 解码失败。
    case decodingFailed(String)
}
