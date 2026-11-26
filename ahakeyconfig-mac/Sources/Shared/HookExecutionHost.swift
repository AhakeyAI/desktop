import Darwin
import Foundation

/// Only known local launcher categories are persisted, never process paths,
/// identifiers, environment values or the Hook input.
public enum HookExecutionHost: String, CaseIterable, Sendable {
    case orca, lobeHub, t3Code, codexDesktop, claudeDesktop, terminal, unidentified

    static func identify(ancestorBundles: [String], environment: [String: String]) -> Self {
        for name in ancestorBundles {
            switch name.lowercased() {
            case "orca.app": return .orca
            case "lobehub.app", "lobe hub.app": return .lobeHub
            case "t3 code.app", "t3code.app": return .t3Code
            case "codex.app": return .codexDesktop
            case "claude.app": return .claudeDesktop
            case "terminal.app", "iterm.app", "iterm2.app": return .terminal
            default: continue
            }
        }
        if environment["ORCA_WORKTREE_ID"]?.isEmpty == false,
           environment["ORCA_TERMINAL_HANDLE"]?.isEmpty == false {
            return .orca
        }
        if environment["T3CODE_HOST_ID"]?.isEmpty == false { return .t3Code }
        return .unidentified
    }

    static func capture() -> Self {
        var pid = getppid()
        var bundles: [String] = []
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        // proc_info.h defines PROC_PIDPATHINFO_MAXSIZE as 4 * MAXPATHLEN.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for _ in 0..<24 {
            guard pid > 1 else { break }
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  info.pbi_uid == geteuid() else { break }
            if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
                let components = URL(fileURLWithPath: String(cString: path)).pathComponents
                if let bundle = components.first(where: { $0.hasSuffix(".app") }) { bundles.append(bundle) }
            }
            guard let parent = Int32(exactly: info.pbi_ppid), parent != pid else { break }
            pid = parent
        }
        return identify(ancestorBundles: bundles, environment: ProcessInfo.processInfo.environment)
    }

    func record(at event: URL) {
        try? Data().write(to: event.appendingPathExtension(rawValue), options: .withoutOverwriting)
    }

    static func recorded(at event: URL) -> Set<Self> {
        Set(allCases.filter { FileManager.default.fileExists(atPath: event.appendingPathExtension($0.rawValue).path) })
    }

    static func removeMarkers(at event: URL) {
        for host in allCases {
            try? FileManager.default.removeItem(at: event.appendingPathExtension(host.rawValue))
        }
    }
}
