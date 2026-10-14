import Foundation

/// A GUI app's PATH often omits Homebrew and the user's shell startup files.
public enum CodexCLIPathResolver {
    public static func installedCLI(
        path: String,
        homeDirectory: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let pathCandidates = path.split(separator: ":").map {
            (String($0) as NSString).appendingPathComponent("codex")
        }
        let standardCandidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            (homeDirectory as NSString).appendingPathComponent(".local/bin/codex"),
        ]
        return (pathCandidates + standardCandidates).first(where: isExecutable)
    }

    public static func bundledCLI(
        homeDirectory: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let applicationDirectories = ["/Applications", (homeDirectory as NSString).appendingPathComponent("Applications")]
        let candidates = applicationDirectories.flatMap { directory in
            [
                directory + "/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
                directory + "/Codex.app/Contents/Resources/codex",
            ]
        }
        return candidates.first(where: isExecutable)
    }
}
