import Foundation
import Speech

/// Immutable recognition facts cross from the audio callback to the UI actor.
struct NativeSpeechRecognitionUpdate: Sendable {
    let text: String?
    let isFinal: Bool
    var completion: SpeechTranscriptAccumulator.Completion? = nil
    var errorDescription: String? = nil

    static func capture(_ result: SFSpeechRecognitionResult?, error: Error?) -> Self {
        var completion: SpeechTranscriptAccumulator.Completion?
        if let result, result.isFinal || result.speechRecognitionMetadata != nil {
            let source = result.bestTranscription.segments
            let segments = source.compactMap { segment -> SpeechTranscriptAccumulator.TimedSegment? in
                guard let span = SpeechTranscriptAccumulator.AudioSpan(start: segment.timestamp, duration: segment.duration) else { return nil }
                return .init(audio: span, textRange: segment.substringRange)
            }
            if segments.count == source.count, let span = SpeechTranscriptAccumulator.AudioSpan.covering(segments.map(\.audio)) {
                completion = .init(audio: span, segments: segments)
            } else {
                completion = result.speechRecognitionMetadata.flatMap {
                    SpeechTranscriptAccumulator.AudioSpan(start: $0.speechStartTimestamp, duration: $0.speechDuration)
                }.map { .init(audio: $0) }
            }
        }
        return .init(text: result?.bestTranscription.formattedString, isFinal: result?.isFinal ?? false,
            completion: completion, errorDescription: error?.localizedDescription)
    }
}
