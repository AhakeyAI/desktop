import Foundation

/// Public GitHub HTML fallback for anonymously rate-limited Release API calls.
/// Only this repository's versioned DMG links with GitHub SHA-256 are accepted.
public enum GitHubReleasePage {
    public static func tag(in html: String) -> String? {
        capture(#"/AhakeyAI/desktop/releases/expanded_assets/([^\"\s<>]+)"#, in: html)
            .flatMap { AppReleaseVersion($0) == nil ? nil : $0 }
    }

    public static func release(tag: String, assetsHTML: String) throws -> AppRelease {
        guard AppReleaseVersion(tag) != nil else { throw URLError(.cannotParseResponse) }
        let expression = try NSRegularExpression(pattern: #"<li\b[^>]*>[\s\S]*?</li>"#)
        let range = NSRange(assetsHTML.startIndex..., in: assetsHTML)
        var assets: [[String: String]] = []
        for match in expression.matches(in: assetsHTML, range: range) {
            guard let r = Range(match.range, in: assetsHTML) else { continue }
            let row = String(assetsHTML[r])
            let prefix = "/AhakeyAI/desktop/releases/download/\(tag)/"
            guard let path = capture(#"href=\"([^\"]+)\""#, in: row), path.hasPrefix(prefix),
                  let digest = capture(#"(sha256:[0-9a-fA-F]{64})\b"#, in: row) else { continue }
            let name = String(path.dropFirst(prefix.count))
            guard name.hasPrefix("AhaKey-Studio-macOS"), name.hasSuffix(".dmg"), !name.contains("/"), !name.contains("%") else { continue }
            assets.append(["name": name, "browser_download_url": "https://github.com" + path, "digest": digest])
        }
        guard !assets.isEmpty else { throw URLError(.cannotParseResponse) }
        let data = try JSONSerialization.data(withJSONObject: ["tag_name": tag,
            "html_url": "https://github.com/AhakeyAI/desktop/releases/tag/\(tag)", "assets": assets])
        return try JSONDecoder().decode(AppRelease.self, from: data)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
