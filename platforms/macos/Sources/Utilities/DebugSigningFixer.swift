import Foundation

/// 本地开发专用：调用 scripts/fix-debug-permissions.sh，
/// 用稳定自签证书重签 dist/AhaKey Studio.app 并重置 TCC 权限。
///
/// 识别"本地开发环境"的方式：检查 app bundle 兄弟目录里是否存在
/// scripts/fix-debug-permissions.sh。只有从源码构建的 dev build
/// 才具备这一条件 —— 正式发布到 /Applications 的 .app 没有兄弟
/// scripts/ 目录，`isAvailable` 会返回 false，UI 不会显示按钮。
///
/// 这样不依赖 `#if DEBUG` 宏，任何构建配置下代码都被编译，
/// 但只在开发环境下真正对外暴露入口。
enum DebugSigningFixer {
    struct Result {
        let success: Bool
        let output: String
    }

    /// 仅当能定位到源码中的修复脚本时才视为"可用"。
    /// 这就是"开发环境 vs 已安装发行版"的运行时区分。
    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: scriptURL.path)
    }

    private static var scriptURL: URL {
        URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()  // .../dist/ 或 安装目录
            .deletingLastPathComponent()  // .../ 项目根 或 /Applications
            .appendingPathComponent("scripts")
            .appendingPathComponent("fix-debug-permissions.sh")
    }

    static func run(completion: @escaping (Result) -> Void) {
        let script = scriptURL
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            completion(Result(
                success: false,
                output: "找不到可执行脚本：\(script.path)\n\n此功能仅在从源码运行的开发构建中可用。"
            ))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let ok = process.terminationStatus == 0
                DispatchQueue.main.async {
                    completion(Result(
                        success: ok,
                        output: ok
                            ? output + "\n请立即退出 AhaKey Studio 并重新启动，按系统提示重新勾选权限即可。"
                            : "脚本执行失败 (exit=\(process.terminationStatus))\n\n\(output)"
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(Result(
                        success: false,
                        output: "无法启动修复脚本: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}
