import Foundation

/// An untimed result replaces the active utterance's earlier hypothesis.
/// Completed audio is tracked separately; never guess boundaries from text overlap.
enum SpeechTranscriptSnapshot {
    static func applying(_ formattedString: String, to previous: String) -> String {
        let snapshot = formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.isEmpty ? previous : snapshot
    }
}

/// One recording can contain several completed utterances even while the
/// recognition task's isFinal remains false.
struct SpeechTranscriptAccumulator {
    struct AudioSpan: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        init?(start: TimeInterval, duration: TimeInterval) {
            guard start.isFinite, duration.isFinite, start >= 0, duration > 0,
                  (start + duration).isFinite else { return nil }
            self.start = start
            self.end = start + duration
        }

        static func covering(_ segments: [Self]) -> Self? {
            guard let start = segments.map(\.start).min(), let end = segments.map(\.end).max() else { return nil }
            return Self(start: start, duration: end - start)
        }
    }

    private struct Utterance {
        let audioSpan: AudioSpan
        let text: String
    }
    private var completed: [Utterance] = []
    private var pending = ""

    var transcript: String {
        // Keep recognized words/punctuation intact and separate distinct utterances.
        (completed.map(\.text) + (pending.isEmpty ? [] : [pending])).joined(separator: " ")
    }

    mutating func apply(_ text: String, audioSpan: AudioSpan?, isFinal: Bool = false) -> String {
        let snapshot = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snapshot.isEmpty else { return transcript }
        if let audioSpan {
            // A revised or cumulative result supersedes only audio it covers.
            // Equal text from disjoint audio represents real repetition.
            completed.removeAll { $0.audioSpan.start < audioSpan.end && audioSpan.start < $0.audioSpan.end }
            completed.append(Utterance(audioSpan: audioSpan, text: snapshot))
            completed.sort { $0.audioSpan.start < $1.audioSpan.start }
            pending = ""
        } else if !(isFinal && pending.isEmpty && completed.last?.text == snapshot) {
            // Ignore an exact duplicate completion without new partials/audio.
            // New untimed partials still revise just the pending utterance.
            pending = SpeechTranscriptSnapshot.applying(snapshot, to: pending)
        }
        return transcript
    }
}
