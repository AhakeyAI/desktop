import Foundation

/// 访问 app bundle 内置的默认 OLED 素材。
/// 资源由 scripts/build-debug.sh 从项目根的 Resources/DefaultOLED/ 拷贝到
/// AhaKey Studio.app/Contents/Resources/DefaultOLED/。
enum DefaultOLEDAssets {
    private static let subdirectory = "DefaultOLED"

    /// 每个 Mode 在工程里预置的出厂 GIF 文件名（不带扩展名）。
    /// 没有内置素材的 Mode 返回 nil，走用户自定义或固件端默认动图。
    static func bundledFileName(for mode: AhaKeyModeSlot) -> String? {
        switch mode {
        case .mode0:
            return "claude_0"
        case .mode1:
            return "cursor_0"
        case .mode2:
            return nil
        }
    }

    /// 解析出 bundle 内该 GIF 的绝对文件路径；资源不存在时返回 nil。
    static func bundledAssetPath(for mode: AhaKeyModeSlot) -> String? {
        guard let name = bundledFileName(for: mode) else { return nil }
        return bundledAssetPath(forName: name)
    }

    /// 按名字查找 bundle 里的 .gif，返回绝对路径。
    static func bundledAssetPath(forName name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: "gif", subdirectory: subdirectory)?.path
    }

    /// 判断一个 localAssetPath 是否指向某个 bundle 内置素材。
    /// 迁移逻辑用：当用户的草稿引用已失效的 bundle 路径（比如换 app 位置、换 mode）时可以安全重写。
    static func isBundledPath(_ path: String) -> Bool {
        guard let resourcesURL = Bundle.main.resourceURL else { return false }
        let resourcesPath = resourcesURL.appendingPathComponent(subdirectory).path
        return path.hasPrefix(resourcesPath + "/")
    }
}
