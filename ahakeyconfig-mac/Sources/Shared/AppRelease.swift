import CryptoKit
import Foundation

public struct AppReleaseVersion: Comparable {
    private let components: [Int]

    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, numbers.count == parts.count,
              numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        components = numbers
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct AppRelease: Decodable {
    public struct Asset: Decodable {
        public let name: String
        public let browserDownloadURL: URL
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let htmlURL: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public func isNewer(than installedVersion: String) -> Bool {
        guard let latest = AppReleaseVersion(tagName),
              let installed = AppReleaseVersion(installedVersion) else { return false }
        return latest > installed
    }

    public var macDMG: Asset? {
        assets.first { $0.name == "AhaKey-Studio-macOS.dmg" && $0.isTrustedDownload }
            ?? assets.first { $0.name.hasPrefix("AhaKey-Studio-macOS") && $0.name.hasSuffix(".dmg") && $0.isTrustedDownload }
    }
}

public extension AppRelease.Asset {
    var isTrustedDownload: Bool {
        browserDownloadURL.scheme == "https" && browserDownloadURL.host == "github.com"
            && digest?.range(of: #"^sha256:[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil
    }

    func verifiesSHA256(_ data: Data) -> Bool {
        guard isTrustedDownload, let expected = digest?.dropFirst("sha256:".count).lowercased() else { return false }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == expected
    }
}
