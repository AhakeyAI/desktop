import Darwin
import Foundation

public protocol LocalStatusHookConfiguration {
    var configurationURLs: [URL] { get }
    func isConfigured() -> Bool
    func update(install: Bool) throws
}

/// Publishes complete hook files without replacing another tool's or the user's files.
struct ManagedStatusHookFile {
    struct Conflict: LocalizedError {
        let url: URL
        var errorDescription: String? { "同名配置已存在：\(url.path)" }
    }

    let url: URL
    let contents: Data
    var executable = false

    enum Ownership: Equatable { case absent, owned, conflict }

    func ownership() throws -> Ownership {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return .absent }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue == contents.count,
              try Data(contentsOf: url) == contents else { return .conflict }
        return .owned
    }

    @discardableResult
    func install() throws -> Bool {
        switch try ownership() {
        case .owned:
            if executable, !FileManager.default.isExecutableFile(atPath: url.path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            return false
        case .conflict: throw Conflict(url: url)
        case .absent: break
        }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".ahakey-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try contents.write(to: stage, options: .withoutOverwriting)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stage.path)
        }
        guard link(stage.path, url.path) == 0 else {
            let code = errno
            if code == EEXIST {
                guard try ownership() == .owned else { throw Conflict(url: url) }
                return false
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return true
    }

    func uninstall() throws {
        if try ownership() == .owned {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func install(_ files: [Self]) throws {
        if let conflict = try files.first(where: { try $0.ownership() == .conflict }) {
            throw Conflict(url: conflict.url)
        }
        var created: [Self] = []
        do {
            for file in files where try file.install() { created.append(file) }
        } catch {
            for file in created.reversed() { try? file.uninstall() }
            throw error
        }
    }
}

enum StatusHookScript {
    static func jsonLiteral(_ path: String) throws -> String {
        try validate(path)
        return String(decoding: try JSONEncoder().encode(path), as: UTF8.self)
    }

    static func shellLiteral(_ path: String) throws -> String {
        try validate(path)
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func validate(_ path: String) throws {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw CocoaError(.fileReadInvalidFileName) }
    }

    static func nodeSender(executable: String, event: String) -> String {
        """
        import { spawn } from "node:child_process";
        const pending = new Map();
        function send(status, session) {
          if (typeof session !== "string" || session.length === 0 || session.length > 256) return;
          if (pending.size >= 256 && !pending.has(session)) return;
          const previous = pending.get(session) ?? Promise.resolve();
          const current = previous.then(() => new Promise(resolve => {
            try {
              const child = spawn(\(executable), ["hook", "\(event)"], { stdio: ["pipe", "ignore", "ignore"] });
              const timeout = setTimeout(() => { child.kill(); resolve(); }, 2500);
              const finish = () => { clearTimeout(timeout); resolve(); };
              child.once("error", finish);
              child.once("close", finish);
              child.stdin.on("error", () => {});
              child.stdin.end(JSON.stringify({ status, session_id: session }));
            } catch { resolve(); }
          }));
          pending.set(session, current);
          void current.then(() => { if (pending.get(session) === current) pending.delete(session); });
        }
        """
    }
}

public enum PassiveStatusHook: String {
    case pi = "PiStatus"
    case openClaw = "OpenClawStatus"

    public var receiptClient: StatusHookReceipts.Client { self == .pi ? .pi : .openClaw }

    public func stateRequest(from data: Data) -> [String: Any]? {
        guard data.count <= 2048, let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let client: WS3TaskClient = self == .pi ? .pi : .openClaw
        guard WS3TaskMetadata(client: client, session: payload.session_id, event: rawValue) != nil else { return nil }
        return [
            "cmd": "state", "value": payload.status.state,
            "task": ["client": client.rawValue, "session": payload.session_id, "event": rawValue]
        ]
    }

    private struct Payload: Decodable {
        enum Status: String, Decodable {
            case running, waiting, done, ended

            var state: Int {
                switch self {
                case .running: return 7
                case .waiting: return 1
                case .done: return 5
                case .ended: return 8
                }
            }
        }

        let status: Status
        let session_id: String
    }
}
