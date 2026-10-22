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
            _ = stream.apply(text, completion: nil)
        }
        _ = stream.apply("长按语音测试", completion: .init(audio: span(2.640, 2.250)))
        for text in ["前", "前后", "前后内", "前后内容", "前后内容都", "前后内容都保留"] {
            _ = stream.apply(text, completion: nil)
        }
        XCTAssertEqual(stream.apply("前后内容都保留", completion: .init(audio: span(7.680, 2.100))),
                       "长按语音测试 前后内容都保留")
    }

    func testSameAudioRevisionReplacesCompletedUtteranceEvenWhenShorter() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("今天晴朗天气很好", completion: .init(audio: span(1, 3)))
        XCTAssertEqual(stream.apply("今天晴朗", completion: .init(audio: span(1, 3))), "今天晴朗")
    }

    func testRealRepeatedUtterancesWithDifferentAudioAreBothKept() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("确认确认", completion: .init(audio: span(1, 1)))
        _ = stream.apply("确认", completion: nil)
        XCTAssertEqual(stream.apply("确认确认", completion: .init(audio: span(4, 1))), "确认确认 确认确认")
    }

    func testCumulativeTimedResultReplacesAllCoveredAudio() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("First.", completion: .init(audio: span(1, 1)))
        _ = stream.apply("Second.", completion: .init(audio: span(4, 1)))
        XCTAssertEqual(stream.apply("First. Second!", completion: .init(audio: span(1, 4))), "First. Second!")
    }

    func testUntimedRevisionsRemainSingleLatestHypothesis() {
        var stream = SpeechTranscriptAccumulator()
        for text in ["长", "常", "长按", "长按测试", "长按测试"] { _ = stream.apply(text, completion: nil) }
        XCTAssertEqual(stream.apply("长按测试", completion: nil), "长按测试")
    }

    func testStopBeforeSecondUtteranceTimingKeepsPendingWords() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("第一句。", completion: .init(audio: span(1, 1)))
        _ = stream.apply("第二", completion: nil)
        _ = stream.apply("第二句。", completion: nil)
        XCTAssertEqual(stream.finalization, .review(previous: "第一句。", latest: "第二句。"))
    }

    func testDuplicateFinalAndEmptySnapshotDoNotRepeatCommittedUtterance() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("已有内容", completion: .init(audio: span(1, 2)))
        _ = stream.apply("", completion: nil)
        XCTAssertEqual(stream.apply("已有内容", completion: .init(audio: span(1, 2))), "已有内容")
        XCTAssertEqual(stream.finalization, .ready("已有内容"))
    }

    func testNewRecordingStateDoesNotCarryPriorWords() {
        var first = SpeechTranscriptAccumulator()
        _ = first.apply("上一段", completion: .init(audio: span(1, 1)))
        var next = SpeechTranscriptAccumulator()
        XCTAssertEqual(next.apply("下一段", completion: .init(audio: span(1, 1))), "下一段")
    }

    func testRecordingStartAtZeroAndAdjacentUtterancesRemainDistinct() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("Yes", completion: .init(audio: span(0, 1)))
        XCTAssertEqual(stream.apply("Yes", completion: .init(audio: span(1, 1))), "Yes Yes")
    }

    func testObservedDuplicateWordRevisionTraceStaysEightCharacters() {
        var stream = SpeechTranscriptAccumulator()
        for text in ["甲", "甲乙", "甲丙乙", "甲丙乙丁", "甲丙乙丁戊", "甲丙乙丁戊己", "甲丙乙丁戊己庚", "甲丙乙丁戊己庚辛", "甲丙乙丁戊己庚辛"] {
            _ = stream.apply(text, completion: nil)
        }
        XCTAssertEqual(stream.apply("甲丙乙丁戊己庚辛", completion: .init(audio: span(1, 2))), "甲丙乙丁戊己庚辛")
    }

    func testEnclosingAudioIncludesPausesInsteadOfSummingSpeechDurations() {
        let covered = SpeechTranscriptAccumulator.AudioSpan.covering([span(1, 0.5), span(5, 1)])
        XCTAssertEqual(covered?.start, 1)
        XCTAssertEqual(covered?.end, 6)
    }

    func testMissingSegmentTimingDoesNotInventAnAudioRange() {
        XCTAssertNil(SpeechTranscriptAccumulator.AudioSpan.covering([]))
    }

    private func cumulativeWords() -> SpeechTranscriptAccumulator.Completion {
        .init(audio: span(1, 4), segments: [
            .init(audio: span(1, 1), textRange: NSRange(location: 0, length: 5)),
            .init(audio: span(4, 1), textRange: NSRange(location: 7, length: 6))])
    }

    func testCumulativeThenTailRevisionKeepsEarlierWordSegments() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("First.", completion: .init(audio: span(1, 1)))
        _ = stream.apply("Second.", completion: .init(audio: span(4, 1)))
        _ = stream.apply("First. Second.", completion: cumulativeWords())
        _ = stream.apply("Second!", completion: .init(audio: span(4, 1)))
        XCTAssertEqual(stream.finalization, .ready("First. Second!"))
    }

    func testUntimedCumulativeDoesNotAutomaticallyDuplicateCompletedPrefix() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("First.", completion: .init(audio: span(1, 1)))
        XCTAssertEqual(stream.apply("First. Second."), "First. Second.")
        XCTAssertEqual(stream.finalization, .review(previous: "First.", latest: "First. Second."))
    }

    func testPartialCoarseAudioCannotSilentlyEraseUncoveredPrefix() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("First. Second.", completion: .init(audio: span(1, 4)))
        _ = stream.apply("Second!", completion: .init(audio: span(4, 1)))
        XCTAssertEqual(stream.finalization, .review(previous: "First. Second.", latest: "Second!"))
    }

    func testLaterDisjointAudioDoesNotClearEarlierUnresolvedEdit() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("First. Second.", completion: .init(audio: span(1, 4)))
        _ = stream.apply("Second!", completion: .init(audio: span(4, 1)))
        _ = stream.apply("Third.", completion: .init(audio: span(7, 1)))
        guard case .review(let previous, let latest) = stream.finalization else { return XCTFail("Unresolved audio cannot be auto-pasted") }
        XCTAssertTrue(previous.contains("First.")); XCTAssertTrue(previous.contains("Third."))
        XCTAssertEqual(latest, "Second!")
    }

    func testCompleteWordCoverageCanResolveEarlierAmbiguity() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("First. Second.", completion: .init(audio: span(1, 4)))
        _ = stream.apply("Second!", completion: .init(audio: span(4, 1)))
        _ = stream.apply("First. Second!", completion: cumulativeWords())
        XCTAssertEqual(stream.finalization, .ready("First. Second!"))
    }

    func testUTF16WordRangesPreserveEmojiWhitespaceAndPunctuation() {
        let text = "“😀，hello!”"
        let source = text as NSString
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply(text, completion: .init(audio: span(1, 2), segments: [
            .init(audio: span(1, 0.5), textRange: source.range(of: "😀")),
            .init(audio: span(2, 1), textRange: source.range(of: "hello"))]))
        XCTAssertEqual(stream.finalization, .ready(text))
    }

    func testInvalidUTF16BoundaryRetainsWholeHypothesisForReview() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("😀", completion: .init(audio: span(1, 1), segments: [
            .init(audio: span(1, 1), textRange: NSRange(location: 0, length: 1))]))
        XCTAssertEqual(stream.finalization, .review(previous: "", latest: "😀"))
    }

    func testRoundoffAtAdjacentBoundaryDoesNotRemovePreviousWords() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("One", completion: .init(audio: span(0.1, 0.2)))
        _ = stream.apply("Two", completion: .init(audio: span(0.3, 0.2)))
        XCTAssertEqual(stream.finalization, .ready("One Two"))
    }

    func testUntimedRepeatedWordsRequireReviewRatherThanLexicalDeletion() {
        var stream = SpeechTranscriptAccumulator()
        _ = stream.apply("确认", completion: .init(audio: span(1, 1)))
        _ = stream.apply("确认")
        XCTAssertEqual(stream.finalization, .review(previous: "确认", latest: "确认"))
    }

    func testTextAndAudioSegmentOrderMustAgree() {
        for starts in [[4.0, 1.0], [1.0, 1.0]] {
            var stream = SpeechTranscriptAccumulator()
            _ = stream.apply("First. Second.", completion: .init(audio: span(1, 4), segments: [
                .init(audio: span(starts[0], 1), textRange: NSRange(location: 0, length: 5)),
                .init(audio: span(starts[1], 1), textRange: NSRange(location: 7, length: 6))]))
            XCTAssertEqual(stream.finalization, .review(previous: "", latest: "First. Second."))
        }
    }

    func testInvalidTimingCannotClaimCompletedAudio() {
        for pair in [(-1.0, 1.0), (1, 0), (1, -1), (.infinity, 1), (1, .nan)] {
            XCTAssertNil(SpeechTranscriptAccumulator.AudioSpan(start: pair.0, duration: pair.1))
        }
    }
}
