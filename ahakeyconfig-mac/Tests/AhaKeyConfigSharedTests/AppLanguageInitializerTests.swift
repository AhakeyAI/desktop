import XCTest
@testable import AhaKeyConfigShared

final class AppLanguageInitializerTests: XCTestCase {
    func testRestoresManuallySelectedLanguageWhenAppleLanguagesDrifts() throws {
        let suite = "AhaKeyLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("zh-Hans", forKey: "AhaKeySelectedLanguage")
        defaults.set(["en-US"], forKey: "AppleLanguages")

        AppLanguageInitializer.applySystemLanguageIfNeeded(defaults: defaults, preferredLanguages: ["en-US"])

        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
        XCTAssertEqual(defaults.string(forKey: "AhaKeySelectedLanguage"), "zh-Hans")
    }

    func testFirstLaunchUsesSupportedSystemLanguage() throws {
        let suite = "AhaKeyLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        AppLanguageInitializer.applySystemLanguageIfNeeded(defaults: defaults, preferredLanguages: ["zh-SG", "en-US"])

        XCTAssertEqual(defaults.string(forKey: "AhaKeySelectedLanguage"), "zh-Hans")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
    }
}
