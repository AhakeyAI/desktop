import Foundation

/// The App, CLI and IDE share the documented global named-hook file.
public struct AntigravityStatusHooks {
    public enum Event: String, CaseIterable {
        case preInvocation = "PreInvocation"
        case stop = "Stop"

        public var hookArgument: String { "Antigravity" + rawValue }
        public var response: String { self == .stop ? #"{"decision":"stop"}"# : "{}" }

        public init?(hookArgument: String) {
            guard hookArgument.hasPrefix("Antigravity") else { return nil }
            self.init(rawValue: String(hookArgument.dropFirst("Antigravity".count)))
        }

        public func stateRequest(from data: Data) -> [String: Any]? {
            guard data.count <= 16 * 1024 * 1024,
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  let conversation = UUID(uuidString: payload.conversationId) else { return nil }
            let state: Int
            switch self {
            case .preInvocation:
                guard let invocation = payload.invocationNum, invocation >= 0 else { return nil }
                state = 7
            case .stop:
                guard let execution = payload.executionNum, execution >= 0,
                      let idle = payload.fullyIdle else { return nil }
                state = idle ? 5 : 7
            }
            return [
                "cmd": "state", "value": state,
                "task": ["client": WS3TaskClient.antigravity.rawValue, "session": conversation.uuidString, "event": hookArgument]
            ]
        }

        private struct Payload: Decodable {
            let conversationId: String
            let invocationNum: Int?
            let executionNum: Int?
            let fullyIdle: Bool?
        }
    }

    public enum Failure: Error { case invalidEntry, invalidConfiguration, conflictingName, configurationChanged }

    private static let name = "ahakey-studio-status"
    public let configurationURL: URL
    private let entryPath: String

    public init(home: URL, entryPath: String) throws {
        guard entryPath.hasPrefix("/"), !entryPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw Failure.invalidEntry }
        configurationURL = home.appendingPathComponent(".gemini/config/hooks.json")
        self.entryPath = entryPath
    }

    public func isConfigured() -> Bool {
        guard let original = try? read() else { return false }
        return isOwned(original.settings[Self.name])
    }

    public func update(install: Bool) throws {
        let original = try read()
        var next = original.settings
        if let current = next[Self.name] {
            guard isOwned(current) else { throw Failure.conflictingName }
            if install { return }
            next.removeValue(forKey: Self.name)
        } else {
            guard install else { return }
            next[Self.name] = definition
        }
        let file = configurationURL.resolvingSymlinksInPath()
        let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard try read().data == original.data else { throw Failure.configurationChanged }
        try data.write(to: file, options: .atomic)
    }

    private func read() throws -> (settings: [String: Any], data: Data?) {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: configurationURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: configurationURL.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw Failure.conflictingName
            }
            return ([:], nil)
        }
        defer { try? handle.close() }
        let limit = 2 * 1024 * 1024
        guard let data = try handle.read(upToCount: limit + 1), data.count <= limit,
              let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.invalidConfiguration }
        return (settings, data)
    }

    private func isOwned(_ value: Any?) -> Bool {
        guard let object = value as? [String: Any] else { return false }
        return NSDictionary(dictionary: object).isEqual(to: definition)
    }

    private var definition: [String: Any] {
        let executable = "'" + entryPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return Dictionary(uniqueKeysWithValues: Event.allCases.map {
            ($0.rawValue, [["type": "command", "command": "\(executable) hook \($0.hookArgument)", "timeout": 5]])
        })
    }
}
