import Foundation

/// A permission-sync summary, never a list of private Codex thread identities.
public struct CodexDesktopLeverStatus: Decodable, Equatable, Sendable {
    public enum Phase: String, Decodable, Sendable { case waiting, working, synchronized, notManaged, notSynchronized, externalChange }
    public let phase: Phase
    public let pendingRecovery: Int
    public let managedSessions: Int
    public let appliesTo: String
    public static func decode(_ data: Data) -> Self? {
        guard data.count <= 4096, let value = try? JSONDecoder().decode(Self.self, from: data),
              (0...32).contains(value.pendingRecovery), (0...32).contains(value.managedSessions),
              value.appliesTo == "nextTurn" else { return nil }
        return value
    }
}
