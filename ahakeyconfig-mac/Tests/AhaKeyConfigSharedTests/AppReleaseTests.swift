import XCTest
@testable import AhaKeyConfigShared

final class AppReleaseTests: XCTestCase {
    private let releaseJSON = """
    {
      "tag_name": "v0.2.3",
      "html_url": "https://github.com/AhakeyAI/desktop/releases/tag/v0.2.3",
      "assets": [{
        "name": "AhaKey-Studio-macOS.dmg",
        "browser_download_url": "https://github.com/AhakeyAI/desktop/releases/download/v0.2.3/AhaKey-Studio-macOS.dmg",
        "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      }]
    }
    """

    func testReleaseComparisonAndAssetSelection() throws {
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(releaseJSON.utf8))
        XCTAssertTrue(release.isNewer(than: "0.2.2"))
        XCTAssertFalse(release.isNewer(than: "0.2.3"))
        XCTAssertFalse(release.isNewer(than: "0.3.0"))
        XCTAssertEqual(release.macDMG?.name, "AhaKey-Studio-macOS.dmg")
    }

    func testUntrustedAssetIsNotOfferedForDownload() throws {
        let modified = releaseJSON.replacingOccurrences(of: "https://github.com/AhakeyAI/desktop/releases/download", with: "https://example.com/download")
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(modified.utf8))
        XCTAssertNil(release.macDMG)
    }
}
