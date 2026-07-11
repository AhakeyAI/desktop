import Foundation

// 扫描插件目录、加载 manifest、拉起所有插件，并管它们的生命周期。
//
// 默认插件目录：
//   ~/Library/Application Support/AhaKeyConfig/plugins/<id>/plugin.json
//
// 可通过环境变量 `AHAKEY_PLUGINS_DIR` 临时覆写（调试用）。
//
// 单个插件加载失败不会影响其他插件 —— 错误写到 stderr，把这个 id 标记为 failed。

public actor PluginManager {
    public struct LoadedPlugin: Sendable {
        public let manifest: PluginManifest
        public let host: PluginHost
        public let initialize: PluginInitializeResult?
    }

    public struct LoadFailure: Sendable {
        public let manifestDirectory: URL
        public let error: String
    }

    private let pluginsRoot: URL
    private let appInfo: HostAppInfo
    private var loaded: [String: LoadedPlugin] = [:]
    private(set) public var failures: [LoadFailure] = []

    public init(
        pluginsRoot: URL = PluginManager.defaultPluginsRoot,
        appInfo: HostAppInfo = .current()
    ) {
        self.pluginsRoot = pluginsRoot
        self.appInfo = appInfo
    }

    public static var defaultPluginsRoot: URL {
        if let override = ProcessInfo.processInfo.environment["AHAKEY_PLUGINS_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/AhaKeyConfig/plugins",
                isDirectory: true
            )
    }

    // MARK: - Discover

    /// 扫描 `pluginsRoot` 下所有一级子目录，挑出有 `plugin.json` 的。
    /// 不抛错（根目录不存在 → 空数组）。
    public func discover() -> [PluginManifest] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: pluginsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var out: [PluginManifest] = []
        for dir in entries {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            do {
                let manifest = try PluginManifest.load(from: dir)
                out.append(manifest)
            } catch {
                failures.append(.init(manifestDirectory: dir, error: "\(error)"))
                FileHandle.standardError.write(
                    Data("[PluginManager] skip \(dir.lastPathComponent): \(error)\n".utf8)
                )
            }
        }
        return out
    }

    // MARK: - Load / Unload

    /// 把发现到的插件全部加载。返回成功数；失败的写到 `failures` 与 stderr。
    @discardableResult
    public func loadAll() async -> Int {
        let manifests = discover()
        var ok = 0
        for m in manifests {
            do {
                try await load(manifest: m)
                ok += 1
            } catch {
                failures.append(.init(manifestDirectory: m.directory, error: "\(error)"))
                FileHandle.standardError.write(
                    Data("[PluginManager] load \(m.id) failed: \(error)\n".utf8)
                )
            }
        }
        return ok
    }

    public func load(manifest: PluginManifest) async throws {
        if loaded[manifest.id] != nil { return } // 幂等

        let ep = manifest.resolvedEntrypoint
        let client = PluginClient(
            executable: ep.executable,
            arguments: ep.arguments,
            environment: ep.environment,
            workingDirectory: ep.workingDirectory
        )
        let host = PluginHost(
            client: client,
            appInfo: appInfo,
            permissions: Set(manifest.permissions)
        )
        await host.registerDefaultHandlers()
        try await client.start()

        // 握手
        let info = try await client.initialize(
            host: appInfo,
            hostMethods: PluginHost.availableHostMethods
        )
        try await client.sendInitialized()

        loaded[manifest.id] = LoadedPlugin(manifest: manifest, host: host, initialize: info)
    }

    public func unloadAll() async {
        for (_, p) in loaded {
            await p.host.client.shutdown()
            await p.host.client.stop()
        }
        loaded.removeAll()
    }

    // MARK: - 查询

    public func allLoaded() -> [LoadedPlugin] {
        Array(loaded.values)
    }

    public func plugin(id: String) -> LoadedPlugin? {
        loaded[id]
    }
}
