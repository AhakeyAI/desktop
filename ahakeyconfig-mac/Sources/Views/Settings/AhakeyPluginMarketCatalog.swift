import Foundation
import AhaKeyPluginKit

/// 插件市场顶部分段。
enum AhakeyPluginMarketSection: String, CaseIterable, Identifiable, Hashable {
    case mine
    case store

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mine: "我的插件"
        case .store: "开源市场"
        }
    }

    var subtitle: String {
        switch self {
        case .mine: "已装与教程"
        case .store: "发现与贡献"
        }
    }
}

/// 插件市场货架条目（本轮静态目录；后续可接远程商店）。
struct AhakeyPluginMarketItem: Identifiable, Equatable, Hashable {
    enum Status: String, Equatable {
        case inDevelopment
        case example

        var title: String {
            switch self {
            case .inDevelopment: "开发中"
            case .example: "示例"
            }
        }
    }

    let id: String
    let name: String
    let version: String
    let summary: String
    let repoPath: String
    let permissions: [String]
    let status: Status
    let systemImage: String
}

enum AhakeyPluginMarketCatalog {
    /// 本机插件安装目录（与 PluginManifest 约定一致）。
    static let localInstallPathHint = "~/Library/Application Support/AhaKeyConfig/plugins/"

    static let items: [AhakeyPluginMarketItem] = [
        AhakeyPluginMarketItem(
            id: "dev.ahakey.keysilk-keypad",
            name: "KeySilk Portable Keypad",
            version: "0.1.0",
            summary: "便携键区适配器：布局/绑定查询、companion 热键安装，以及 openUrl / pasteText 等宿主动作分发。",
            repoPath: "plugins/keysilk-keypad",
            permissions: [
                "host/getInfo",
                "host/log",
                "host/getSwitchState",
                "host/openUrl",
                "host/openPath",
                "host/pasteText",
                "host/registerGlobalHotkey",
            ],
            status: .inDevelopment,
            systemImage: "keyboard"
        ),
        AhakeyPluginMarketItem(
            id: "dev.ahakey.example.typescript",
            name: "TypeScript Showcase",
            version: "0.1.0",
            summary: "TypeScript SDK 示例：握手宿主、读取设备信息与拨杆状态，适合上手插件开发。",
            repoPath: "sdks/typescript/examples/hello-plugin",
            permissions: [
                "host/getInfo",
                "host/log",
                "host/getSwitchState",
            ],
            status: .example,
            systemImage: "curlybraces"
        ),
        AhakeyPluginMarketItem(
            id: "dev.ahakey.example.lever-counter",
            name: "Lever Counter",
            version: "0.1.0",
            summary: "拨杆翻档计数示例：统计自动/手动档切换次数与停留时长，演示后台轮询与本地快照。",
            repoPath: "sdks/typescript/examples/lever-counter",
            permissions: [
                "host/getInfo",
                "host/log",
                "host/getSwitchState",
            ],
            status: .example,
            systemImage: "switch.2"
        ),
    ]
}

/// 本机已装插件轻量发现（只读 plugin.json，不拉起进程）。
enum AhakeyInstalledPluginsStore {
    struct InstalledPlugin: Identifiable, Equatable, Hashable {
        let id: String
        let name: String
        let version: String
        let permissions: [String]
        let directoryPath: String
    }

    /// 扫描 `PluginManager.defaultPluginsRoot` 下一级子目录中的 `plugin.json`。
    static func discover() -> [InstalledPlugin] {
        let root = PluginManager.defaultPluginsRoot
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var out: [InstalledPlugin] = []
        for dir in entries {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            guard let manifest = try? PluginManifest.load(from: dir) else { continue }
            out.append(
                InstalledPlugin(
                    id: manifest.id,
                    name: manifest.name,
                    version: manifest.version,
                    permissions: manifest.permissions,
                    directoryPath: dir.path
                )
            )
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
