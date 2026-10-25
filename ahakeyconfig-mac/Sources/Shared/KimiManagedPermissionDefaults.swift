import Foundation

/// Owns the default scalar, never claims to control a loaded Desktop/TUI session.
public enum KimiManagedPermissionDefaults {
    public enum Outcome: Equatable {
        case updated, restored, unchanged, userOverride, unmanaged, invalid, writeFailed, missing
    }
    private struct Journal: Codable {
        var version = 1
        let configPath: String
        let layout: String
        let original: String?
        var applied: String
        var lever: Int
        var yielded = false
        var pending = false
        var beforeWrite: String?
    }
    static func journalURL(_ config: URL) -> URL {
        config.appendingPathExtension("ahakey.managed-permission.json")
    }
    private static func readMode(_ config: URL, layout: KimiConfigPolicySync.Layout) throws -> String? {
        let text = try String(contentsOf: config, encoding: .utf8)
        let (value, _) = try KimiConfigPolicySync.locate(text, layout: layout)
        return layout == .nativeV2 ? value?.nativeMode : value.map { $0.enabled ? "true" : "false" }
    }
    private static func readJournal(_ config: URL) throws -> Journal? {
        let url = journalURL(config)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8192 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let value = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
        let native = value.layout == KimiConfigPolicySync.Layout.nativeV2.rawValue
        let modes = native ? ["auto", "manual", "yolo"] : ["true", "false"]
        guard value.version == 1, value.configPath == config.standardizedFileURL.path,
              native || value.layout == KimiConfigPolicySync.Layout.legacyPython.rawValue,
              value.lever == 0 || value.lever == 1,
              (native ? ["auto", "manual"] : modes).contains(value.applied),
              value.original == nil || modes.contains(value.original!),
              value.beforeWrite == nil || modes.contains(value.beforeWrite!) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }
    private static func save(_ journal: Journal, config: URL) throws {
        let url = journalURL(config)
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func ownsCurrent(_ journal: Journal, _ current: String?) -> Bool {
        !journal.yielded && (current == journal.applied || journal.pending && current == journal.beforeWrite)
    }
    private static func replaceMode(_ mode: String?, expecting expected: String?,
                                    configURL: URL, layout: KimiConfigPolicySync.Layout) -> KimiPermissionModeSync.Outcome {
        if layout == .nativeV2 {
            return KimiPermissionModeSync.replaceMode(mode, expecting: expected, configURL: configURL)
        }
        do {
            guard mode == nil || mode == "true" || mode == "false" else { return .unsupportedSyntax(reason: "invalid boolean") }
            let bytes = Array(try Data(contentsOf: configURL))
            guard let text = String(bytes: bytes, encoding: .utf8) else { return .unreadableConfig }
            let (value, insertion) = try KimiConfigPolicySync.locate(text, layout: layout)
            let current = value.map { $0.enabled ? "true" : "false" }
            guard current == expected else { return .conflict }
            guard current != mode else { return .alreadyDesired }
            var output = bytes
            if let value {
                if let mode { output.replaceSubrange(value.range, with: Array(mode.utf8)) }
                else {
                    let statements = try TomlPolicyLocator.statements(in: text)
                    guard let statement = statements.first(where: {
                        if case .assignment(let path) = $0.kind {
                            return path == ["default_yolo"] && $0.range.contains(value.range.lowerBound)
                        }
                        return false
                    }) else { return .unsupportedSyntax(reason: "missing assignment") }
                    output.removeSubrange(statement.range.lowerBound..<value.range.upperBound)
                }
            } else if let mode {
                let newline = text.contains("\r\n") ? "\r\n" : "\n"
                let before = insertion > 0 && ![10, 13].contains(bytes[insertion - 1]) ? newline : ""
                output.insert(contentsOf: Array((before + "default_yolo = " + mode + newline).utf8), at: insertion)
            }
            return KimiPermissionModeSync.write(output, to: configURL) ? .replaced : .writeFailed
        } catch { return .unsupportedSyntax(reason: "invalid config") }
    }

    public static func synchronize(switchState: Int?, configURL: URL,
                                   controlDirectory: URL = ApprovalAutomationControl.productionDirectory,
                                   layout: KimiConfigPolicySync.Layout = .nativeV2) -> Outcome {
        ApprovalAutomationControl.locked(directory: controlDirectory) {
            guard switchState == 0 || switchState == 1,
                  ApprovalAutomationControl.enabledUnlocked(.kimi, directory: controlDirectory) else {
                let result = restoreUnlocked(configURL: configURL)
                if result == .restored || result == .userOverride || result == .unmanaged {
                    guard KimiConfigPolicySync.record(configURL, owned: false, directory: controlDirectory) else {
                        return .writeFailed
                    }
                }
                return result
            }
            guard FileManager.default.fileExists(atPath: configURL.path) else { return .missing }
            do {
                let current = try readMode(configURL, layout: layout)
                let state = switchState!
                let desired = layout == .nativeV2 ? (state == 0 ? "auto" : "manual") : (state == 0 ? "true" : "false")
                var journal = try readJournal(configURL)
                if let journal, journal.layout != layout.rawValue { return .invalid }
                if var prior = journal {
                    if !ownsCurrent(prior, current) {
                        if prior.lever == state {
                            if !prior.yielded {
                                prior.yielded = true
                                try save(prior, config: configURL)
                            }
                            return .userOverride
                        }
                        // A new physical lever action explicitly resumes management.
                        // Preserve the user's newer choice as the restoration baseline.
                        journal = Journal(configPath: configURL.standardizedFileURL.path,
                                          layout: layout.rawValue, original: current, applied: desired, lever: state)
                    } else {
                        if current == desired, prior.lever == state, !prior.pending { return .unchanged }
                        prior.applied = desired
                        prior.lever = state
                        journal = prior
                    }
                } else {
                    journal = Journal(configPath: configURL.standardizedFileURL.path,
                                      layout: layout.rawValue, original: current, applied: desired, lever: state)
                }
                guard KimiConfigPolicySync.record(configURL, owned: true, directory: controlDirectory) else {
                    return .writeFailed
                }
                // Write intent before the configuration so crash recovery can inspect the actual scalar.
                journal!.beforeWrite = current
                journal!.pending = true
                try save(journal!, config: configURL)
                switch replaceMode(desired, expecting: current, configURL: configURL, layout: layout) {
                case .inserted, .replaced, .alreadyDesired:
                    journal!.pending = false
                    try save(journal!, config: configURL)
                    return current == desired ? .unchanged : .updated
                case .conflict: return .userOverride
                case .writeFailed: return .writeFailed
                default: return .invalid
                }
            } catch { return .invalid }
        } ?? .writeFailed
    }

    /// Caller holds the shared approval-control lock, including pause/uninstall.
    static func restoreUnlocked(configURL: URL) -> Outcome {
        do {
            guard let journal = try readJournal(configURL) else { return .unmanaged }
            guard FileManager.default.fileExists(atPath: configURL.path) else { return .missing }
            let layout: KimiConfigPolicySync.Layout = journal.layout == KimiConfigPolicySync.Layout.nativeV2.rawValue ? .nativeV2 : .legacyPython
            let current = try readMode(configURL, layout: layout)
            let owned = ownsCurrent(journal, current)
            if owned {
                switch replaceMode(journal.original, expecting: current, configURL: configURL, layout: layout) {
                case .inserted, .replaced, .alreadyDesired: break
                case .conflict: return .userOverride
                case .writeFailed: return .writeFailed
                default: return .invalid
                }
            }
            try FileManager.default.removeItem(at: journalURL(configURL))
            return owned ? .restored : .userOverride
        } catch { return .invalid }
    }
}
