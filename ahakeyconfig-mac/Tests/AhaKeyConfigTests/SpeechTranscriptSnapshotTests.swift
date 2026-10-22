import XCTest
@testable import AhaKeyConfig

final class SpeechTranscriptSnapshotTests: XCTestCase {
    func testRevisedShortHypothesisDoesNotDuplicatePrefix() {
        let partials = ["长", "常", "长按", "长按测试"]
        let actual = partials.reduce("") { SpeechTranscriptSnapshot.applying($1, to: $0) }
        XCTAssertEqual(actual, "长按测试")
    }

    func testAnonymizedObservedRevisionTraceRemainsEightCharacters() {
        // Same equality/prefix structure as the observed 8 -> 10 character failure.
        let partials = ["甲", "甲乙", "甲丙乙", "甲丙乙丁", "甲丙乙丁戊", "甲丙乙丁戊己", "甲丙乙丁戊己庚", "甲丙乙丁戊己庚辛", "甲丙乙丁戊己庚辛"]
        let actual = partials.reduce("") { SpeechTranscriptSnapshot.applying($1, to: $0) }
        XCTAssertEqual(actual, "甲丙乙丁戊己庚辛")
    }

    func testFinalRevisionCanShortenEarlierHypothesis() {
        let actual = SpeechTranscriptSnapshot.applying("今天晴朗", to: "今天晴朗天气很好")
        XCTAssertEqual(actual, "今天晴朗")
    }

    func testActualRepeatedWordsArePreserved() {
        XCTAssertEqual(SpeechTranscriptSnapshot.applying("对对，就是这样", to: "对"), "对对，就是这样")
    }

    func testLongPauseAndPunctuationRemainInLatestSnapshot() {
        XCTAssertEqual(SpeechTranscriptSnapshot.applying("第一句。第二句", to: "第一句。"), "第一句。第二句")
        XCTAssertEqual(SpeechTranscriptSnapshot.applying("第一句。第二句。", to: "第一句。第二句"), "第一句。第二句。")
    }

    func testEmptyInterimRetainsLastUsableSnapshot() {
        XCTAssertEqual(SpeechTranscriptSnapshot.applying("  ", to: "已有内容"), "已有内容")
    }
}
