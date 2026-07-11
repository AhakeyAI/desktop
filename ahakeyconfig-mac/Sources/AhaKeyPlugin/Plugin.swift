import AhaKeyPluginKit
import Foundation

// AhaKey Plugin demo executable —— 把 `AhaKeyPluginKit` 当 SDK 走一遍 manager 流程：
//   1. 扫描 `~/Library/Application Support/AhaKeyConfig/plugins/`
//      （或环境变量 `AHAKEY_PLUGINS_DIR` 指定的目录）
//   2. 按 manifest 拉起每个插件 + 握手
//   3. 列出加载结果
//   4. 停一会儿（让插件有机会反向调用 host）
//   5. 全部 shutdown
//
// 真实主 app 直接 `import AhaKeyPluginKit` 使用 `PluginManager`，不依赖这个 executable。
// 这里只是给 `swift run Plugin` 一个能跑的入口，便于本地验证骨架。

@main
struct PluginDemoMain {
    static func main() async {
        let manager = PluginManager()
        let count = await manager.loadAll()

        let plugins = await manager.allLoaded()
        if plugins.isEmpty {
            FileHandle.standardError.write(Data(
                """
                [plugin-demo] no plugins loaded. \
                drop a plugin.json into \(PluginManager.defaultPluginsRoot.path) \
                or set AHAKEY_PLUGINS_DIR=<path> and rerun.

                """.utf8
            ))
        } else {
            FileHandle.standardError.write(Data(
                "[plugin-demo] loaded \(count) plugin(s):\n".utf8
            ))
            for p in plugins {
                let reported = p.initialize?.name ?? "<no name>"
                FileHandle.standardError.write(Data(
                    "  - \(p.manifest.id) v\(p.manifest.version) [plugin says: \(reported)]\n".utf8
                ))
            }
        }

        // 给插件 1 秒做反向 RPC 之类的事，再 shutdown。
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await manager.unloadAll()
    }
}
