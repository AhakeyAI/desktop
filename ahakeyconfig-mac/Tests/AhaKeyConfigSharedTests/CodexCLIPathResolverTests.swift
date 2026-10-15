import XCTest
@testable import AhaKeyConfigShared

final class CodexCLIPathResolverTests: XCTestCase {
    func testFindsHomebrewCLIWhenGUIPathOmitsIt() {
        let installed = CodexCLIPathResolver.installedCLI(path: "/usr/bin:/bin", homeDirectory: "/Users/test") {
            $0 == "/opt/homebrew/bin/codex"
        }
        XCTAssertEqual(installed, "/opt/homebrew/bin/codex")
    }

    func testSkipsBrokenLocalSymlinkAndFindsBundledChatGPTCLI() {
        let installed = CodexCLIPathResolver.installedCLI(path: "/usr/bin:/bin", homeDirectory: "/Users/test") { _ in false }
        let bundled = CodexCLIPathResolver.bundledCLI(homeDirectory: "/Users/test") {
            $0 == "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        }
        XCTAssertNil(installed)
        XCTAssertEqual(bundled, "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
    }

    func testPrefersWorkingCLIOnCurrentPath() {
        let installed = CodexCLIPathResolver.installedCLI(path: "/custom/bin:/usr/bin", homeDirectory: "/Users/test") {
            $0 == "/custom/bin/codex" || $0 == "/opt/homebrew/bin/codex"
        }
        XCTAssertEqual(installed, "/custom/bin/codex")
    }
}
