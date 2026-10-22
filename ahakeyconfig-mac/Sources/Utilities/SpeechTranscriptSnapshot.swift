import Foundation

/// A result from the same recognition task replaces its earlier hypothesis.
/// Do not join lexical overlaps: revisions may insert or remove earlier words.
enum SpeechTranscriptSnapshot {
    static func applying(_ formattedString: String, to previous: String) -> String {
        let snapshot = formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.isEmpty ? previous : snapshot
    }
}
