import CryptoKit
import Foundation

public enum WS3TaskClient: String, Codable, Sendable { case claude, cursor, codex, kimi }

/// Only a real session identifier travels with a hook. Never substitute cwd,
/// command text, truncated diagnostic IDs or one shared identifier per IDE.
public struct WS3TaskMetadata: Equatable, Sendable {
    public let client: WS3TaskClient
    private let session: String
    public let event: String
    public let terminal: WS3TerminalTaskIdentity?

    public init?(client: WS3TaskClient, session: String, event: String, terminal: WS3TerminalTaskIdentity? = nil) {
        guard !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              session.utf8.count <= 256, !session.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              event.utf8.count <= 64, event != "SubagentStop" else { return nil }
        self.client = client; self.session = session; self.event = event; self.terminal = terminal
    }

    public init?(dictionary: [String: String]) {
        guard let name = dictionary["client"], let client = WS3TaskClient(rawValue: name),
              let session = dictionary["session"], let event = dictionary["event"] else { return nil }
        self.init(client: client, session: session, event: event, terminal: WS3TerminalTaskIdentity(dictionary: dictionary))
    }

    public var reference: String {
        SHA256.hash(data: Data((client.rawValue + "\u{0}" + session).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    public static func enrich(_ request: [String: Any], client: WS3TaskClient, event: String, stdin: Data) -> [String: Any] {
        guard stdin.count <= 65_536,
              let body = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any],
              let session = (client == .cursor ? body["conversation_id"] as? String : nil) ?? body["session_id"] as? String,
              let metadata = Self(client: client, session: session, event: event) else { return request }
        var request = request
        request["task"] = ["client": client.rawValue, "session": metadata.session, "event": metadata.event]
        return request
    }

    /// Shared-state hook routes only. Specialized permission/Codex routes supply
    /// their client explicitly; unknown event names never acquire an identity.
    public static func client(for event: String) -> WS3TaskClient? {
        switch event {
        case "Notification", "PostToolUse", "SessionStart", "Stop", "TaskCompleted", "UserPromptSubmit", "SessionEnd", "PreCompact": return .claude
        case "sessionStart", "sessionEnd", "postToolUse", "stop": return .cursor
        case "KimiNotification", "KimiSessionStart", "KimiSessionEnd", "KimiPostToolUse", "KimiUserPromptSubmit", "KimiStop": return .kimi
        default: return nil
        }
    }
}

public struct WS3ObservedTask: Codable, Equatable, Sendable {
    public let slot: Int
    public let client: WS3TaskClient
    public let reference: String
    public let state: WS3TaskState
    public let foreground: Bool?
}

public struct WS3TaskOverview: Codable, Equatable, Sendable {
    public let connected: Bool
    public let tasks: [WS3ObservedTask]
    /// Counts discarded events, not unique tasks (which cannot be inferred).
    public let unrepresentedEvents: Int
    /// Optional fields keep older read-only Agent responses decodable.
    public let requestedMode: WS3PresentationMode?
    public let presentationBusy: Bool?

    public init(connected: Bool, tasks: [WS3ObservedTask], unrepresentedEvents: Int,
                requestedMode: WS3PresentationMode? = nil, presentationBusy: Bool? = nil) {
        self.connected = connected; self.tasks = tasks; self.unrepresentedEvents = unrepresentedEvents
        self.requestedMode = requestedMode; self.presentationBusy = presentationBusy
    }

    public func reportingPresentation(mode: WS3PresentationMode?, busy: Bool) -> Self {
        Self(connected: connected, tasks: tasks, unrepresentedEvents: unrepresentedEvents,
             requestedMode: mode, presentationBusy: busy)
    }

    public static func decode(_ data: Data) -> Self? {
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              value.tasks.count <= 4, value.unrepresentedEvents >= 0,
              value.connected || value.tasks.isEmpty,
              value.connected || value.requestedMode == nil,
              Set(value.tasks.map(\.slot)).count == value.tasks.count,
              value.tasks.allSatisfy({ (0..<4).contains($0.slot) && $0.reference.count == 64 && $0.reference.allSatisfy { $0.isHexDigit && $0.isASCII } }) else { return nil }
        return value
    }
}

/// Ephemeral observations for one live BLE connection. No approval decisions,
/// persistence, foreground guesses, background replay or device writes.
public struct WS3TaskRegistry {
    private struct Entry {
        let reference: String
        let client: WS3TaskClient
        let terminal: WS3TerminalTaskIdentity?
        var state: WS3TaskState
        var updatedAt: TimeInterval
    }
    private var entries: [Entry?] = Array(repeating: nil, count: 4)
    private var unrepresentedEvents = 0
    private var foregroundTerminal: WS3TerminalTaskIdentity?
    public init() {}
    public var nextExpiry: TimeInterval? { entries.compactMap { $0.map { $0.updatedAt + 300 } }.min() }

    public mutating func clear() { self = Self() }

    @discardableResult
    public mutating func observe(_ metadata: WS3TaskMetadata, state: UInt8, at now: TimeInterval) -> Bool {
        observe(reference: metadata.reference, client: metadata.client, event: metadata.event, terminal: metadata.terminal, state: state, at: now)
    }

    @discardableResult
    public mutating func observe(_ observation: WS3LiveTaskEvent, at now: TimeInterval) -> Bool {
        guard observation.isValid(at: now) else { return false }
        return observe(reference: observation.reference, client: observation.client, event: observation.event, terminal: observation.terminal,
            state: observation.state, at: now)
    }

    private mutating func observe(reference key: String, client: WS3TaskClient, event: String, terminal: WS3TerminalTaskIdentity?, state: UInt8, at now: TimeInterval) -> Bool {
        expire(at: now)
        let existing = entries.firstIndex { $0?.reference == key }
        if state == 8 {
            guard let existing else { return false }
            entries[existing] = nil; return true
        }
        let taskState: WS3TaskState
        switch state {
        case 0: taskState = event == "PreCompact" ? .running : .waiting
        case 1: taskState = .waiting
        case 2, 3, 7: taskState = .running
        case 5, 6: taskState = .done
        default: return false // SessionStart/idle is not a running task.
        }
        // Late stop events do not invent tasks we never observed running.
        if taskState == .done, existing == nil { return false }
        let oldestDone = entries.indices.filter { entries[$0]?.state == .done }
            .min { entries[$0]!.updatedAt < entries[$1]!.updatedAt }
        guard let slot = existing ?? entries.firstIndex(where: { $0 == nil }) ?? oldestDone else {
            unrepresentedEvents = min(unrepresentedEvents + 1, 1_000_000); return false
        }
        entries[slot] = Entry(reference: key, client: client, terminal: terminal, state: taskState, updatedAt: now)
        return true
    }

    public mutating func overview(connected: Bool, at now: TimeInterval) -> WS3TaskOverview {
        if !connected { clear() }
        expire(at: now)
        let focused = foregroundReference
        let tasks = entries.enumerated().compactMap { index, entry -> WS3ObservedTask? in
            guard let entry else { return nil }
            return WS3ObservedTask(slot: index, client: entry.client, reference: entry.reference, state: entry.state, foreground: entry.reference == focused)
        }
        return WS3TaskOverview(connected: connected, tasks: tasks, unrepresentedEvents: unrepresentedEvents)
    }

    public mutating func snapshot(at now: TimeInterval) -> WS3TaskSnapshot {
        expire(at: now)
        let focused = foregroundReference
        return WS3TaskSnapshot(slots: entries.map { $0.map { WS3TaskSlot(state: $0.state, foreground: $0.reference == focused) } })!
    }

    /// Focus changes never refresh a task's Hook timestamp or create tasks.
    @discardableResult
    public mutating func setForegroundTerminal(_ terminal: WS3TerminalTaskIdentity?) -> Bool {
        guard foregroundTerminal != terminal else { return false }
        foregroundTerminal = terminal
        return true
    }
    private var foregroundReference: String? {
        guard let foregroundTerminal else { return nil }
        let matches = entries.compactMap { $0 }.filter { $0.terminal == foregroundTerminal }
        // A terminal group can host multiple conversations. Do not pick one by
        // recency, state, or slot order when its identity is ambiguous.
        return matches.count == 1 ? matches[0].reference : nil
    }

    private mutating func expire(at now: TimeInterval) {
        for index in entries.indices {
            if let entry = entries[index], now - entry.updatedAt >= 300 || now < entry.updatedAt { entries[index] = nil }
        }
    }
}
