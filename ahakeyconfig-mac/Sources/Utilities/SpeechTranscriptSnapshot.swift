import Foundation

/// Untimed hypotheses revise only the active utterance, never lexical overlaps.
enum SpeechTranscriptSnapshot {
    static func applying(_ formattedString: String, to previous: String) -> String {
        let snapshot = formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.isEmpty ? previous : snapshot
    }
}

struct SpeechTranscriptAccumulator {
    struct AudioSpan: Equatable, Sendable {
        let start: TimeInterval
        let end: TimeInterval
        private static let roundingTolerance = 0.000001

        init?(start: TimeInterval, duration: TimeInterval) {
            let end = start + duration
            guard start.isFinite, duration.isFinite, start >= 0, duration > 0,
                  end.isFinite, end > start else { return nil }
            self.start = start
            self.end = end
        }
        static func covering(_ segments: [Self]) -> Self? {
            guard let start = segments.map(\.start).min(), let end = segments.map(\.end).max() else { return nil }
            return Self(start: start, duration: end - start)
        }
        func overlaps(_ other: Self) -> Bool {
            min(end, other.end) - max(start, other.start) > Self.roundingTolerance
        }
        func covers(_ other: Self) -> Bool {
            start <= other.start + Self.roundingTolerance && end + Self.roundingTolerance >= other.end
        }
    }

    struct TimedSegment: Sendable {
        let audio: AudioSpan
        let textRange: NSRange
    }
    struct Completion: Sendable {
        let audio: AudioSpan
        let segments: [TimedSegment]
        init(audio: AudioSpan, segments: [TimedSegment] = []) {
            self.audio = audio
            self.segments = segments
        }
    }
    enum Finalization: Equatable {
        case ready(String)
        case review(previous: String, latest: String)
        case empty
    }

    private struct Piece {
        let audio: AudioSpan
        let text: String
        let startsSnapshot: Bool
    }
    private struct UnresolvedEdit {
        let audio: AudioSpan
        let text: String
    }
    private var pieces: [Piece] = []
    private var unresolved: [UnresolvedEdit] = []
    private var pending = ""

    private var completedText: String {
        var result = ""
        for piece in pieces {
            if piece.startsSnapshot, !result.isEmpty,
               result.last?.isWhitespace == false, piece.text.first?.isWhitespace == false { result += " " }
            result += piece.text
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var finalization: Finalization {
        if !unresolved.isEmpty || (!pieces.isEmpty && !pending.isEmpty) {
            let latest = pending.isEmpty ? unresolved.last?.text ?? "" : pending
            let earlierEdits = pending.isEmpty ? Array(unresolved.dropLast()) : unresolved
            let previous = ([completedText] + earlierEdits.map(\.text)).filter { !$0.isEmpty }.joined(separator: "\n\n")
            return .review(previous: previous, latest: latest)
        }
        let value = pending.isEmpty ? completedText : pending
        return value.isEmpty ? .empty : .ready(value)
    }

    /// Preview is a hypothesis, not an authorization to paste it.
    var transcript: String {
        // Avoid rebuilding the completed prefix for every interim callback.
        if !pending.isEmpty { return pending }
        if let latest = unresolved.last { return latest.text }
        return completedText
    }

    mutating func apply(_ text: String, completion: Completion? = nil) -> String {
        let snapshot = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snapshot.isEmpty else { return transcript }
        guard let completion else {
            pending = SpeechTranscriptSnapshot.applying(snapshot, to: pending)
            return transcript
        }
        let overlapping = pieces.filter { $0.audio.overlaps(completion.audio) }
        guard overlapping.allSatisfy({ completion.audio.covers($0.audio) }),
              let incoming = Self.split(text, completion: completion) else {
            // A coarse/invalid observation cannot silently erase uncovered audio.
            unresolved.removeAll { $0.audio == completion.audio }
            unresolved.append(.init(audio: completion.audio, text: snapshot))
            pending = ""
            return transcript
        }
        pieces.removeAll { $0.audio.overlaps(completion.audio) }
        pieces.append(contentsOf: incoming)
        pieces.sort { $0.audio.start < $1.audio.start }
        unresolved.removeAll { completion.audio.covers($0.audio) }
        pending = ""
        return transcript
    }

    private static func split(_ text: String, completion: Completion) -> [Piece]? {
        let segments = completion.segments
        if segments.isEmpty {
            return [Piece(audio: completion.audio, text: text.trimmingCharacters(in: .whitespacesAndNewlines), startsSnapshot: true)]
        }
        let length = text.utf16.count
        var previousEnd = 0
        var previousAudioStart: TimeInterval?
        for segment in segments {
            let range = segment.textRange
            guard range.location >= previousEnd, range.location <= length, range.length > 0,
                  range.length <= length - range.location, validatedRange(range, in: text) != nil,
                  completion.audio.covers(segment.audio),
                  previousAudioStart.map({ segment.audio.start > $0 }) ?? true else { return nil }
            previousEnd = range.location + range.length
            previousAudioStart = segment.audio.start
        }
        var result: [Piece] = []
        for (index, segment) in segments.enumerated() {
            let lower = index == 0 ? 0 : segment.textRange.location
            let upper = index + 1 < segments.count ? segments[index + 1].textRange.location : length
            guard let range = validatedRange(NSRange(location: lower, length: upper - lower), in: text) else { return nil }
            result.append(.init(audio: segment.audio, text: String(text[range]), startsSnapshot: index == 0))
        }
        return result
    }
    private static func validatedRange(_ range: NSRange, in text: String) -> Range<String.Index>? {
        let utf16 = text.utf16
        guard range.location >= 0, range.length >= 0, range.location <= utf16.count,
              range.length <= utf16.count - range.location,
              let lower = String.Index(utf16.index(utf16.startIndex, offsetBy: range.location), within: text),
              let upper = String.Index(utf16.index(utf16.startIndex, offsetBy: range.location + range.length), within: text) else { return nil }
        return lower..<upper
    }

}
