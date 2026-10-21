import XCTest
@testable import AhaKeyConfigShared

final class GitHubReleasePageTests: XCTestCase {
    func testOnlyVersionedRepositoryAssetWithDigestIsAccepted() throws {
        XCTAssertEqual(GitHubReleasePage.tag(in: #"src="/AhakeyAI/desktop/releases/expanded_assets/v0.2.4""#), "v0.2.4")
        XCTAssertNil(GitHubReleasePage.tag(in: #"src="/attacker/desktop/releases/expanded_assets/v0.2.4""#))
        XCTAssertNil(GitHubReleasePage.tag(in: #"src="/AhakeyAI/desktop/releases/expanded_assets/../../other""#))
        let html = "<li><a href=\"/AhakeyAI/desktop/releases/download/v0.2.4/AhaKey-Studio-macOS.dmg\">DMG</a>sha256:\(String(repeating: "a", count: 64))</li>"
        XCTAssertNotNil(try GitHubReleasePage.release(tag: "v0.2.4", assetsHTML: html).macDMG)
        XCTAssertThrowsError(try GitHubReleasePage.release(tag: "v0.2.4", assetsHTML: html.replacingOccurrences(of: "sha256:", with: "missing:")))
        XCTAssertThrowsError(try GitHubReleasePage.release(tag: "v0.2.4", assetsHTML: html.replacingOccurrences(of: "/AhakeyAI/", with: "/attacker/")))
    }
}
