import Foundation

public struct PiStatusHooks: LocalStatusHookConfiguration {
    private let file: ManagedStatusHookFile
    public var configurationURL: URL { file.url }
    public var configurationURLs: [URL] { [configurationURL] }

    public init(home: URL, agentDirectory: String? = nil, entryPath: String) throws {
        let executable = try StatusHookScript.jsonLiteral(entryPath)
        if let agentDirectory { try StatusHookScript.validate(agentDirectory) }
        let directory = agentDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".pi/agent")
        let configuration = directory.appendingPathComponent("extensions/ahakey-studio.ts")
        let configurationPath = try StatusHookScript.jsonLiteral(configuration.path)
        let script = StatusHookScript.nodeSender(executable: executable, event: PassiveStatusHook.pi.rawValue) + """

        import { existsSync } from "node:fs";
        export default function AhaKeyStudio(pi) {
          const publish = (status, ctx) => {
            if (existsSync(\(configurationPath))) send(status, ctx.sessionManager.getSessionId());
          };
          pi.on("agent_start", (_event, ctx) => publish("running", ctx));
          // agent_end also fires between automatic retries; only final settlement is done.
          pi.on("agent_settled", (event, ctx) => publish(event.aborted ? "ended" : "done", ctx));
          pi.on("session_shutdown", (_event, ctx) => publish("ended", ctx));
        }
        """
        file = ManagedStatusHookFile(url: configuration, contents: Data(script.utf8))
    }

    public func isConfigured() -> Bool { (try? file.ownership()) == .owned }

    public func update(install: Bool) throws {
        if install { try file.install() }
        else { try file.uninstall() }
    }
}
