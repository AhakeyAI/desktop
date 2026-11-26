import Foundation

public struct ClineStatusHooks: LocalStatusHookConfiguration {
    public enum Event: String, CaseIterable {
        case start = "TaskStart"
        case resume = "TaskResume"
        case complete = "TaskComplete"
        case cancel = "TaskCancel"
        case error = "TaskError"
        case shutdown = "SessionShutdown"

        public var hookArgument: String { "Cline" + rawValue }
        public static let response = #"{"cancel":false}"#

        public init?(hookArgument: String) {
            guard hookArgument.hasPrefix("Cline") else { return nil }
            self.init(rawValue: String(hookArgument.dropFirst("Cline".count)))
        }

        public func stateRequest(from data: Data) -> [String: Any]? {
            guard data.count <= 16 * 1024 * 1024,
                  let input = try? JSONDecoder().decode(Input.self, from: data),
                  let task = input.taskId ?? input.task_id ?? input.session_id,
                  WS3TaskMetadata(client: .cline, session: task, event: hookArgument) != nil else { return nil }
            if let name = input.hookName ?? input.hook_event_name,
               name != rawValue && name != runtimeName { return nil }
            guard input.parent_agent_id == nil else { return nil }
            let value: Int
            switch self {
            case .start, .resume: value = 7
            case .complete: value = 5
            case .cancel, .error, .shutdown: value = 8
            }
            return ["cmd": "state", "value": value,
                    "task": ["client": "cline", "session": task, "event": hookArgument]]
        }

        private var runtimeName: String {
            switch self {
            case .start: return "agent_start"
            case .resume: return "agent_resume"
            case .complete: return "agent_end"
            case .cancel: return "agent_abort"
            case .error: return "agent_error"
            case .shutdown: return "session_shutdown"
            }
        }

        private struct Input: Decodable {
            let taskId: String?
            let task_id: String?
            let session_id: String?
            let hookName: String?
            let hook_event_name: String?
            let parent_agent_id: String?
        }
    }

    private let files: [ManagedStatusHookFile]
    public var configurationURLs: [URL] { files.map(\.url) }

    public init(home: URL, entryPath: String) throws {
        let executable = try StatusHookScript.shellLiteral(entryPath)
        let directory = home.appendingPathComponent(".cline/hooks", isDirectory: true)
        files = Event.allCases.map { event in
            let script = """
                #!/bin/sh
                if [ -x \(executable) ]; then
                  exec \(executable) hook \(event.hookArgument)
                fi
                printf '%s\\n' '\(Event.response)'
                """ + "\n"
            return ManagedStatusHookFile(url: directory.appendingPathComponent(event.rawValue),
                                         contents: Data(script.utf8), executable: true)
        }
    }

    public func isConfigured() -> Bool { files.contains { (try? $0.ownership()) == .owned } }

    public func update(install: Bool) throws {
        if install { try ManagedStatusHookFile.install(files) }
        else { for file in files { try file.uninstall() } }
    }
}
