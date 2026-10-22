import XCTest
@testable import AhaKeyConfig

final class SpeechTranscriptAccumulatorTests: XCTestCase {
    private func span(_ start: Double, _ duration: Double) -> SpeechTranscriptAccumulator.AudioSpan {
        SpeechTranscriptAccumulator.AudioSpan(start: start, duration: duration)!
    }

    func testCapturedPauseTraceKeepsBothUtterancesWithoutDuplicatingPartials() {
        var stream = SpeechTranscriptAccumulator()
        // Actual observation sizes/timing; only the volunteered test text is used.
        for text in ["长", "长按", "长按语音", "长按语音测", "长按语音测试"] {
            _ = stream.apply(text, audioSpan: nil)
        }
        _ = stream.apply("长按语音测试", audioSpan: span(2.640, 2.250))
        for text in ["前", "前后", "前后内", "前后内容", "前后内容都", "前后内容都保留"] {
            _ = stream.apply(text, audioSpan: nil)
        }
        XCTAssertEqual(stream.apply("前后内容都保留", audioSpan: span(7.680, 2.100), isFinal: true),
                       "长按语音测试 前后内容都保留")
    }

    func testSameAudioRevisionReplacesCompletedUtteranceEvenWhenShorter() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("今天晴朗天气很好", audioSpan: span(1, 3))
        XCTAssertEqual(stream.apply("今天晴朗", audioSpan: span(1.1, 2.7), isFinal: true), "今天晴朗")
    }

    func testRealRepeatedUtterancesWithDifferentAudioAreBothKept() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("确认确认", audioSpan: span(1, 1))
        _ = stream.apply("确认", audioSpan: nil)
        XCTAssertEqual(stream.apply("确认确认", audioSpan: span(4, 1), isFinal: true), "确认确认 确认确认")
    }

    func testCumulativeTimedResultReplacesAllCoveredAudio() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("First.", audioSpan: span(1, 1))
        _ = stream.apply("Second.", audioSpan: span(4, 1))
        XCTAssertEqual(stream.apply("First. Second!", audioSpan: span(1, 4), isFinal: true), "First. Second!")
    }

    func testUntimedRevisionsRemainSingleLatestHypothesis() {
        var stream = SpeechTranscriptAccumulator()
        for text in ["长", "常", "长按", "长按测试", "长按测试"] { _ = stream.apply(text, audioSpan: nil) }
        XCTAssertEqual(stream.apply("长按测试", audioSpan: nil, isFinal: true), "长按测试")
    }

    func testStopBeforeSecondUtteranceTimingKeepsPendingWords() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("第一句。", audioSpan: span(1, 1))
        _ = stream.apply("第二", audioSpan: nil)
        XCTAssertEqual(stream.apply("第二句。", audioSpan: nil, isFinal: true), "第一句。 第二句。")
    }

    func testDuplicateFinalAndEmptySnapshotDoNotRepeatCommittedUtterance() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("已有内容", audioSpan: span(1, 2))
        _ = stream.apply("", audioSpan: nil)
        XCTAssertEqual(stream.apply("已有内容", audioSpan: nil, isFinal: true), "已有内容")
    }

    func testNewRecordingStateDoesNotCarryPriorWords() {
        var first = SpeechTranscriptAccumulator()
        _ = first.apply("上一段", audioSpan: span(1, 1))
        var next = SpeechTranscriptAccumulator()
        XCTAssertEqual(next.apply("下一段", audioSpan: span(1, 1), isFinal: true), "下一段")
    }

    func testRecordingStartAtZeroAndAdjacentUtterancesRemainDistinct() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("Yes", audioSpan: span(0, 1))
        XCTAssertEqual(stream.apply("Yes", audioSpan: span(1, 1), isFinal: true), "Yes Yes")
    }

    func testObservedDuplicateWordRevisionTraceStaysEightCharacters() {
        var stream = SpeechTranscriptAccumulator()
        for text in ["甲", "甲乙", "甲丙乙", "甲丙乙丁", "甲丙乙丁戊", "甲丙乙丁戊己", "甲丙乙丁戊己庚", "甲丙乙丁戊己庚辛", "甲丙乙丁戊己庚辛"] {
            _ = stream.apply(text, audioSpan: nil)
        }
        XCTAssertEqual(stream.apply("甲丙乙丁戊己庚辛", audioSpan: span(1, 2), isFinal: true), "甲丙乙丁戊己庚辛")
    }

    func testEnclosingAudioIncludesPausesInsteadOfSummingSpeechDurations() {
        let covered = SpeechTranscriptAccumulator.AudioSpan.covering([span(1, 0.5), span(5, 1)])
        XCTAssertEqual(covered?.start, 1)
        XCTAssertEqual(covered?.end, 6)
    }

    func testMissingSegmentTimingDoesNotInventAnAudioRange() {
        XCTAssertNil(SpeechTranscriptAccumulator.AudioSpan.covering([]))
    }

    func testInvalidTimingCannotClaimCompletedAudio() {
        for pair in [(-1.0, 1.0), (1, 0), (1, -1), (.infinity, 1), (1, .nan)] {
            XCTAssertNil(SpeechTranscriptAccumulator.AudioSpan(start: pair.0, duration: pair.1))
        }
    }
}
