import Foundation

struct DeferredVoiceTranscript: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
enum VoiceTranscriptCompletion {
    enum Result: Equatable {
        case ready(String)
        case deferred(String)
    }

    /// The real finalization path checks on both sides of the cloud suspension.
    /// A late result is retained for explicit copying, never injected into a
    /// newer recording's input or allowed to overwrite its HUD.
    static func run(text: String, ticket: UUID, currentTicket: () -> UUID,
                    process: (String) async -> String) async -> Result {
        guard currentTicket() == ticket else { return .deferred(text) }
        let output = await process(text)
        return currentTicket() == ticket ? .ready(output) : .deferred(output)
    }
}
