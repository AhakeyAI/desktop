import XCTest

@testable import AhaKeyConfig

final class SpeechLocaleResolverTests: XCTestCase {
    /// 取自真机 `SFSpeechRecognizer.supportedLocales()` 的一个子集，含 en 的多个地区变体。
    private let supported: Set<Locale> = [
        "zh-CN", "zh-TW", "zh-HK",
        "en-US", "en-GB", "en-AU", "en-IN",
        "ja-JP", "de-DE",
    ].map(Locale.init(identifier:)).reduce(into: Set<Locale>()) { $0.insert($1) }

    /// 稳定的 stub：不依赖本机语音组件，测试才有确定的期望值。
    private func normalize(_ language: String) -> Locale? {
        let defaults = ["en": "en-US", "zh": "zh-CN", "ja": "ja-JP", "de": "de-DE"]
        return defaults[language].map(Locale.init(identifier:))
    }

    // MARK: match

    func testMatchesLanguageAndRegionExactly() {
        // zh-Hans-CN 带脚本码，仍应落到 zh-CN 而不是 zh-TW / zh-HK
        let hit = SpeechLocaleResolver.match("zh-Hans-CN", in: supported, normalize: normalize)
        XCTAssertEqual(hit?.identifier, "zh-CN")
    }

    func testFallsBackToLanguageWhenRegionHasNoRecognizer() {
        // 没有 en-CN 识别器，退到该语言的默认地区
        let hit = SpeechLocaleResolver.match("en-CN", in: supported, normalize: normalize)
        XCTAssertEqual(hit?.identifier, "en-US")
    }

    func testLanguageOnlyFallbackIsDeterministic() {
        // en 在 supported 里有 4 个变体；Set 无序，结果必须始终一致
        let results = (0 ..< 20).map { _ in
            SpeechLocaleResolver.match("en-CN", in: supported, normalize: normalize)?.identifier
        }
        XCTAssertEqual(Set(results), ["en-US"])
    }

    func testReturnsNilForUnparsableTag() {
        XCTAssertNil(SpeechLocaleResolver.match("", in: supported, normalize: normalize))
    }

    func testReturnsNilWhenNormalizedLocaleIsUnsupported() {
        // 归一化给出的地区不在支持列表里时，不能硬塞给识别器
        let hit = SpeechLocaleResolver.match("fr-FR", in: supported) { _ in Locale(identifier: "fr-FR") }
        XCTAssertNil(hit)
    }

    // MARK: resolve

    func testExplicitPreferenceWinsOverSystemLanguages() {
        let hit = SpeechLocaleResolver.resolve(
            preference: "zh-CN",
            preferredLanguages: ["en-CN", "zh-Hans-CN"],
            supported: supported,
            normalize: normalize
        )
        XCTAssertEqual(hit?.identifier, "zh-CN")
    }

    func testUnsupportedPreferenceIsIgnored() {
        // 用户选过的语言在别的机器上可能不受支持，此时应回到自动推断而不是失败
        let hit = SpeechLocaleResolver.resolve(
            preference: "ko-KR",
            preferredLanguages: ["ja-JP"],
            supported: supported,
            normalize: normalize
        )
        XCTAssertEqual(hit?.identifier, "ja-JP")
    }

    func testAutomaticKeepsPreferredLanguageOrder() {
        // 首选列表第一项能匹配上就用它，不因为后面有"更精确"的项而改变顺序语义
        let hit = SpeechLocaleResolver.resolve(
            preference: "",
            preferredLanguages: ["en-CN", "zh-Hans-CN"],
            supported: supported,
            normalize: normalize
        )
        XCTAssertEqual(hit?.identifier, "en-US")
    }

    func testAutomaticSkipsUnmatchableEntries() {
        let hit = SpeechLocaleResolver.resolve(
            preference: "",
            preferredLanguages: ["xx-YY", "ja-JP"],
            supported: supported,
            normalize: normalize
        )
        XCTAssertEqual(hit?.identifier, "ja-JP")
    }

    func testReturnsNilWhenNothingMatches() {
        let hit = SpeechLocaleResolver.resolve(
            preference: "",
            preferredLanguages: ["xx-YY"],
            supported: supported,
            normalize: normalize
        )
        XCTAssertNil(hit)
    }
}
