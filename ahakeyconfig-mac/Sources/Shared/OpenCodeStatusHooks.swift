import Darwin
import Foundation

/// OpenCode V1 automatically loads global JavaScript plugins at startup.
public struct OpenCodeStatusHooks {
    public static let hookArgument = "OpenCodeStatus"
    public let configurationURL: URL
    private let script: Data

    public enum Failure: Error { case invalidPath, conflictingFile }

    public init(home: URL, configHome: String? = nil, entryPath: String) throws {
        guard entryPath.hasPrefix("/"), configHome.map({ $0.hasPrefix("/") }) ?? true,
              ![entryPath, configHome ?? ""].joined().unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw Failure.invalidPath }
        let config = configHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config")
        configurationURL = config.appendingPathComponent("opencode/plugins/ahakey-studio.js")
        let executable = String(decoding: try JSONEncoder().encode(entryPath), as: UTF8.self)
        script = Data("""
            import { spawn } from "node:child_process";
            export const AhaKeyStudio = async () => ({
              event: async ({ event }) => {
                const value = event.properties;
                const status = event.type === "session.status" ? value?.status?.type
                  : event.type === "session.deleted" ? "deleted" : undefined;
                const session = status === "deleted" ? value?.info?.id : value?.sessionID;
                if (typeof session !== "string" || !["busy", "retry", "idle", "deleted"].includes(status)) return;
                try {
                  const child = spawn(\(executable), ["hook", "\(Self.hookArgument)"], { stdio: ["pipe", "ignore", "ignore"] });
                  child.on("error", () => {});
                  child.stdin.on("error", () => {});
                  child.stdin.end(JSON.stringify({ status, session_id: session }));
                } catch {}
              },
            });
            """.utf8)
    }

    public func isConfigured() -> Bool { (try? installedScript()) == script }

    public func update(install: Bool) throws {
        if let current = try installedScript() {
            guard current == script else { throw Failure.conflictingFile }
            if !install { try FileManager.default.removeItem(at: configurationURL) }
            return
        }
        guard install else { return }
        let parent = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".ahakey-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try script.write(to: stage, options: .withoutOverwriting)
        if link(stage.path, configurationURL.path) != 0 {
            let code = errno
            if code == EEXIST {
                guard isConfigured() else { throw Failure.conflictingFile }
            } else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            }
        }
    }

    private func installedScript() throws -> Data? {
        let file = configurationURL.path
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: file)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 32_768 else { throw Failure.conflictingFile }
        return try Data(contentsOf: configurationURL)
    }

    public static func stateRequest(from data: Data) -> [String: Any]? {
        guard data.count <= 1024,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              WS3TaskMetadata(client: .openCode, session: payload.session_id, event: hookArgument) != nil else { return nil }
        return ["cmd": "state", "value": payload.status.state,
                "task": ["client": WS3TaskClient.openCode.rawValue, "session": payload.session_id, "event": hookArgument]]
    }

    private struct Payload: Decodable {
        enum Status: String, Decodable {
            case busy, retry, idle, deleted
            var state: Int {
                switch self {
                case .busy, .retry: return 7
                case .idle: return 5
                case .deleted: return 8
                }
            }
        }
        let status: Status
        let session_id: String
    }
}
