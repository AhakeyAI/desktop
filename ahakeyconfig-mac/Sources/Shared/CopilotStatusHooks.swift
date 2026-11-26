import Darwin
import Foundation

/// The Copilot CLI adapter owns a dedicated user-level hook file. Repository
/// and other user hooks can coexist with it without sharing a JSON document.
public struct CopilotStatusHooks {
    public enum Event: String, CaseIterable, Sendable {
        case promptSubmitted = "UserPromptSubmit"
        case turnFinished = "Stop"
        case sessionEnded = "SessionEnd"

        public var hookArgument: String { "Copilot" + rawValue }

        public init?(hookArgument: String) {
            guard hookArgument.hasPrefix("Copilot") else { return nil }
            self.init(rawValue: String(hookArgument.dropFirst("Copilot".count)))
        }

        public func stateRequest(from payload: Data) -> [String: Any]? {
            let value: Int
            switch self {
            case .promptSubmitted: value = 7
            case .turnFinished: value = 5
            case .sessionEnded: value = 8
            }
            let request = WS3TaskMetadata.enrich(
                ["cmd": "state", "value": value], client: .copilot,
                event: hookArgument, stdin: payload, expectedEvent: rawValue
            )
            // A mismatched or old payload must not change the global LED state.
            return request["task"] == nil ? nil : request
        }
    }

    public enum Status: Equatable { case absent, configured, conflict }
    public enum Failure: Error, Equatable { case invalidHome, invalidEntry, conflictingFile }

    public let configurationURL: URL
    private let entryPath: String

    /// Pass the same COPILOT_HOME used to start Copilot CLI when it overrides
    /// the default. A custom home is interpreted by Copilot, not this app.
    public init(home: URL, copilotHome: String? = nil, entryPath: String) throws {
        guard Self.isAbsolutePath(home.path),
              copilotHome.map(Self.isAbsolutePath) ?? true else { throw Failure.invalidHome }
        guard Self.isAbsolutePath(entryPath) else { throw Failure.invalidEntry }
        let root = copilotHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".copilot", isDirectory: true)
        configurationURL = root.appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent("ahakey-studio.json")
        self.entryPath = entryPath
    }

    public func status() throws -> Status {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return .absent
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 32_768 else { return .conflict }
        let data = try Data(contentsOf: configurationURL)
        guard let installed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let encoded = try? JSONSerialization.data(withJSONObject: installed, options: [.sortedKeys]),
              encoded == (try JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys]))
        else { return .conflict }
        return .configured
    }

    public func install() throws {
        switch try status() {
        case .configured: return
        case .conflict: throw Failure.conflictingFile
        case .absent: break
        }
        let parent = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(".ahakey-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staged) }
        let data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: staged, options: .withoutOverwriting)
        // Atomically make the complete document visible without replacing a
        // concurrent external file at this path.
        guard link(staged.path, configurationURL.path) == 0 else {
            let code = errno
            if code == EEXIST {
                if try status() == .configured { return }
                throw Failure.conflictingFile
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }

    public func uninstall() throws {
        switch try status() {
        case .absent: return
        case .conflict: throw Failure.conflictingFile
        case .configured: try FileManager.default.removeItem(at: configurationURL)
        }
    }

    private var configuration: [String: Any] {
        let hooks = Dictionary(uniqueKeysWithValues: Event.allCases.map { event in
            let handler: [String: Any] = [
                "type": "command", "exec": entryPath,
                "args": ["hook", event.hookArgument], "timeoutSec": 5,
            ]
            return (event.rawValue, [handler])
        })
        return ["version": 1, "hooks": hooks]
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
