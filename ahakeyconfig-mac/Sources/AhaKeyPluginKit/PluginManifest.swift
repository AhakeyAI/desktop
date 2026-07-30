import Foundation

// 一个插件目录的清单文件（`plugin.json`），决定宿主怎么发现、启动、信任这个插件。
//
// 目录约定：
//   ~/Library/Application Support/AhaKeyConfig/plugins/<id>/plugin.json
//
// 最小示例：
// ```json
// {
//   "id": "com.example.hello",
//   "name": "Hello Plugin",
//   "version": "0.1.0",
//   "entrypoint": {
//     "command": "python3",
//     "args": ["${pluginDir}/main.py"]
//   },
//   "permissions": ["host/log", "host/getInfo"]
// }
// ```
//
// 设计取舍：
// - `entrypoint.command` 不要求绝对路径；宿主统一用 `/usr/bin/env <command>` 拉起，
//   走系统 PATH。要写死可执行用绝对路径，env 也会原样转发。
// - `${pluginDir}` 是 args / env 里的字符串占位符，解析时替换成 manifest 所在目录的绝对路径。
// - `permissions` 是白名单：只有在这个列表里的 `host/*` method 能被该插件调用，
//   未声明的会直接回 method-not-found（-32601）。

public struct PluginManifest: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let entrypoint: Entrypoint
    public let permissions: [String]

    /// manifest 文件所在目录（解析时由 loader 注入；不会被序列化到 JSON）。
    public var directory: URL = URL(fileURLWithPath: "/")

    public struct Entrypoint: Codable, Sendable, Equatable {
        public let command: String
        public let args: [String]
        public let env: [String: String]?

        public init(command: String, args: [String] = [], env: [String: String]? = nil) {
            self.command = command
            self.args = args
            self.env = env
        }
    }

    public init(
        id: String,
        name: String,
        version: String,
        entrypoint: Entrypoint,
        permissions: [String] = [],
        directory: URL = URL(fileURLWithPath: "/")
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.entrypoint = entrypoint
        self.permissions = permissions
        self.directory = directory
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, entrypoint, permissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        entrypoint = try c.decode(Entrypoint.self, forKey: .entrypoint)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        directory = URL(fileURLWithPath: "/")
    }
}

// MARK: - 加载

public enum PluginManifestError: Error, Sendable {
    case fileNotFound(URL)
    case decode(URL, String)
}

public extension PluginManifest {
    /// 从目录加载 `plugin.json`；解析失败抛 `PluginManifestError`。
    static func load(from directory: URL) throws -> PluginManifest {
        let url = directory.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PluginManifestError.fileNotFound(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PluginManifestError.decode(url, "\(error)")
        }
        do {
            var manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            manifest.directory = directory
            return manifest
        } catch {
            throw PluginManifestError.decode(url, "\(error)")
        }
    }

    /// 把字符串里所有 `${pluginDir}` 替换成 manifest 所在目录的绝对路径。
    func substitute(_ s: String) -> String {
        s.replacingOccurrences(of: "${pluginDir}", with: directory.path)
    }

    /// 解析好的、可直接交给 `Process` 的子进程描述。
    var resolvedEntrypoint: ResolvedEntrypoint {
        ResolvedEntrypoint(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [entrypoint.command] + entrypoint.args.map(substitute),
            environment: entrypoint.env?.mapValues(substitute),
            workingDirectory: directory
        )
    }
}

public struct ResolvedEntrypoint: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]?
    public let workingDirectory: URL
}
