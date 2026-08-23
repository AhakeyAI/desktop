import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyPathsTests: XCTestCase {
    func testRuntimeHookSocketLivesUnderPrivateApplicationSupportDirectory() {
        XCTAssertEqual(
            AhaKeyPaths.runtimeHookSocketURL,
            AhaKeyPaths.applicationSupportDirectory
                .appendingPathComponent("private", isDirectory: true)
                .appendingPathComponent("hook.sock")
        )
    }
}
