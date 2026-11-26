import Darwin
import Foundation

/// Publishes a local native plugin. OpenClaw owns whether local plugins are enabled.
public struct OpenClawStatusHooks: LocalStatusHookConfiguration {
    public static let pluginID = "ahakey-studio-status"

    private let directory: URL
    private let files: [ManagedStatusHookFile]
    public var configurationURLs: [URL] { files.map(\.url) }

    public init(home: URL, stateDirectory: String? = nil, entryPath: String) throws {
        let executable = try StatusHookScript.jsonLiteral(entryPath)
        if let stateDirectory { try StatusHookScript.validate(stateDirectory) }
        let root = stateDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".openclaw")
        let id = Self.pluginID
        let directory = root.appendingPathComponent("extensions/\(id)", isDirectory: true)
        self.directory = directory
        let manifest = directory.appendingPathComponent("openclaw.plugin.json")
        let manifestPath = try StatusHookScript.jsonLiteral(manifest.path)
        let script = StatusHookScript.nodeSender(executable: executable, event: PassiveStatusHook.openClaw.rawValue) + """

        import { createHash } from "node:crypto";
        import { existsSync } from "node:fs";
        export default {
          id: "\(id)",
          name: "AhaKey Studio Status",
          register(api) {
            const publish = (status, key) => {
              if (typeof key !== "string" || !key || key.length > 1024 || !existsSync(\(manifestPath))) return;
              send(status, createHash("sha256").update(key).digest("hex"));
            };
            const active = new Map();
            api.agent?.events?.registerAgentEventSubscription?.({
              id: "status-lifecycle", streams: ["lifecycle"], phases: ["start", "end", "error"],
              payload: "metadata",
              handle(event) {
                const key = event.sessionKey;
                if (typeof key !== "string" || !key || typeof event.runId !== "string") return;
                if (event.data.phase === "start") {
                  if (active.size >= 256 && !active.has(key)) return;
                  active.set(key, event.runId);
                  publish("running", key);
                } else if (event.data.executionSettled === true && active.get(key) === event.runId) {
                  active.delete(key);
                  publish(event.data.phase === "error" || event.data.aborted ? "ended" : "done", key);
                }
              },
            });
            api.on("session_end", (event, ctx) => {
              if (event.reason === "compaction") return;
              const key = ctx?.sessionKey ?? event.sessionKey;
              active.delete(key);
              publish("ended", key);
            });
          },
        };
        """
        files = [
            ManagedStatusHookFile(url: manifest, contents: Data("""
                {"id":"\(id)","name":"AhaKey Studio Status","activation":{"onStartup":true},"configSchema":{"type":"object","additionalProperties":false}}
                """.utf8)),
            ManagedStatusHookFile(url: directory.appendingPathComponent("package.json"), contents: Data("""
                {"name":"\(id)","version":"1.0.0","type":"module","openclaw":{"extensions":["./index.js"]}}
                """.utf8)),
            ManagedStatusHookFile(url: directory.appendingPathComponent("index.js"), contents: Data(script.utf8))
        ]
    }

    public func isConfigured() -> Bool {
        isDirectory && files.allSatisfy { (try? $0.ownership()) == .owned }
    }

    public func update(install: Bool) throws {
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: directory.path) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw ManagedStatusHookFile.Conflict(url: directory)
            }
            if install {
                guard isConfigured() else { throw ManagedStatusHookFile.Conflict(url: directory) }
            } else if isConfigured() {
                for file in files { try file.uninstall() }
                if try manager.contentsOfDirectory(atPath: directory.path).isEmpty {
                    try manager.removeItem(at: directory)
                }
            }
            return
        }
        guard install else { return }
        let parent = directory.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        // Keep the staged plugin outside the discovery directory.
        let stage = parent.deletingLastPathComponent().appendingPathComponent(".ahakey-\(UUID().uuidString)")
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stage) }
        for file in files {
            try file.contents.write(to: stage.appendingPathComponent(file.url.lastPathComponent))
        }
        guard renamex_np(stage.path, directory.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST, isConfigured() { return }
            if code == EEXIST { throw ManagedStatusHookFile.Conflict(url: directory) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }

    private var isDirectory: Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        return attributes?[.type] as? FileAttributeType == .typeDirectory
    }
}
