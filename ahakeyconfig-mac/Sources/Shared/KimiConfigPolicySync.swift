import Foundation

/// Root permission scalar only; nested keys and multiline strings are not settings.
public enum KimiConfigPolicySync {
    public enum Layout: String { case legacyPython = "legacy", nativeV2 = "native-v2" }
    public struct Location: Equatable {
        public let layout: Layout
        public let root: URL
        let validSource: Bool
        init(layout: Layout, root: URL, validSource: Bool = true) {
            self.layout = layout; self.root = root; self.validSource = validSource
        }
        public var isValid: Bool { validSource && root.isFileURL && !root.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
        public var configURL: URL { root.appendingPathComponent("config.toml") }
    }
    public static var productionLocation: Location { location() }
    public static func location(home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executables supplied: [URL]? = nil) -> Location {
        let nativeRoot: URL
        if let path = environment["KIMI_CODE_HOME"], path.hasPrefix("/"), !path.contains("\n"), !path.contains("\0") {
            nativeRoot = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } else { nativeRoot = home.appendingPathComponent(".kimi-code") }
        if environment["AHAKEY_KIMI_LAYOUT"] == Layout.legacyPython.rawValue {
            return Location(layout: .legacyPython, root: home.appendingPathComponent(".kimi"))
        }
        if let marker = environment["AHAKEY_KIMI_LAYOUT"], marker != Layout.nativeV2.rawValue {
            return Location(layout: .nativeV2, root: nativeRoot, validSource: false)
        }
        if let path = environment["KIMI_CODE_HOME"], !path.isEmpty,
           (!path.hasPrefix("/") || path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })) {
            return Location(layout: .nativeV2, root: nativeRoot, validSource: false)
        }
        if environment["AHAKEY_KIMI_LAYOUT"] == Layout.nativeV2.rawValue || environment["KIMI_CODE_HOME"]?.hasPrefix("/") == true {
            return Location(layout: .nativeV2, root: nativeRoot)
        }
        let candidates = supplied ?? (environment["PATH", default: ""].split(separator: ":").prefix(32)
            .filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: String($0)).appendingPathComponent("kimi") } +
            [home.appendingPathComponent(".kimi-code/bin/kimi"), home.appendingPathComponent(".local/bin/kimi")])
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            let resolved = candidate.resolvingSymlinksInPath()
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
                  attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            guard let handle = try? FileHandle(forReadingFrom: resolved) else { continue }
            let header = (try? handle.read(upToCount: 4)) ?? Data()
            try? handle.close()
            // The native v2 distribution is a single Mach-O executable; the
            // supported legacy uv installation is a Python/shebang launcher.
            let nativeHeaders: Set<Data> = [Data([0xCF, 0xFA, 0xED, 0xFE]), Data([0xFE, 0xED, 0xFA, 0xCF]),
                Data([0xCA, 0xFE, 0xBA, 0xBE]), Data([0xBE, 0xBA, 0xFE, 0xCA])]
            return Location(layout: nativeHeaders.contains(header) ? .nativeV2 : .legacyPython,
                root: nativeHeaders.contains(header) ? nativeRoot : home.appendingPathComponent(".kimi"))
        }
        return Location(layout: .legacyPython, root: home.appendingPathComponent(".kimi"))
    }
    public enum Outcome: Equatable { case unchanged, updated, missing, invalid, writeFailed, notOwned, disabled, unsupportedRuntime }
    public static var productionConfigURL: URL { productionLocation.configURL }
    static func leaseURL(_ url: URL) -> URL { url.appendingPathExtension("ahakey-auto-lease") }

    public static func apply(auto: Bool) -> Outcome {
        let location = productionLocation
        return apply(auto: auto, location: location, controlDirectory: ApprovalAutomationControl.productionDirectory)
    }
    static func apply(auto: Bool, location: Location, controlDirectory: URL) -> Outcome {
        guard location.isValid else { return .invalid }
        // Native v2 defaults affect future sessions, not a running terminal's
        // approval gate. Do not create unattended sessions until we can revoke
        // their live authority when the physical lever changes or Agent stops.
        guard location.layout == .legacyPython else { return .unsupportedRuntime }
        return apply(auto: auto, configURL: location.configURL, controlDirectory: controlDirectory, layout: location.layout)
    }
    static func apply(auto: Bool, configURL: URL, controlDirectory: URL, layout: Layout = .legacyPython) -> Outcome {
        ApprovalAutomationControl.locked(directory: controlDirectory) {
            if auto && !ApprovalAutomationControl.enabledUnlocked(.kimi, directory: controlDirectory) { return .disabled }
            if auto {
                guard FileManager.default.fileExists(atPath: configURL.path) else { return .missing }
                guard let data = try? Data(contentsOf: configURL), let text = String(data: data, encoding: .utf8),
                      let (value, _) = try? locate(text, layout: layout) else { return .invalid }
                if value?.enabled == true, value?.legacyOwned != true,
                   !FileManager.default.fileExists(atPath: leaseURL(configURL).path) { return .unchanged }
                guard record(configURL, owned: true, directory: controlDirectory) else { return .writeFailed }
            }
            let result = update(auto: auto, configURL: configURL, layout: layout)
            if result == .updated || result == .unchanged || !FileManager.default.fileExists(atPath: leaseURL(configURL).path) {
                if !auto || !FileManager.default.fileExists(atPath: leaseURL(configURL).path) {
                    guard record(configURL, owned: false, directory: controlDirectory) else { return .writeFailed }
                }
            }
            return result
        } ?? .writeFailed
    }

    /// A CLI can have a different KIMI_CODE_HOME from the GUI. Keep only paths
    /// whose auto policy we own, so stopping/uninstalling can revoke them too.
    static func ownedConfigURLs(directory: URL) -> [URL]? {
        let file = directory.appendingPathComponent("kimi-owned-configs.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536,
              let data = try? Data(contentsOf: file), let paths = try? JSONDecoder().decode([String].self, from: data), paths.count <= 256,
              paths.allSatisfy({ $0.hasPrefix("/") && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else { return nil }
        return paths.map { URL(fileURLWithPath: $0) }
    }
    @discardableResult
    static func record(_ config: URL, owned: Bool, directory: URL) -> Bool {
        guard config.isFileURL, !config.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        guard let known = ownedConfigURLs(directory: directory) else { return false }
        let previous = Set(known.map(\.path))
        var paths = previous
        if owned { paths.insert(config.standardizedFileURL.path) } else { paths.remove(config.standardizedFileURL.path) }
        guard paths.count <= 256 else { return false }
        let file = directory.appendingPathComponent("kimi-owned-configs.json")
        if paths == previous, !paths.isEmpty || !FileManager.default.fileExists(atPath: file.path) { return true }
        do {
            if paths.isEmpty {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            } else {
                let data = try JSONEncoder().encode(paths.sorted())
                guard data.count <= 65_536 else { return false }
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            return true
        } catch { return false }
    }
    struct Value { let range: Range<Int>; let enabled: Bool; let legacyOwned: Bool; let nativeMode: String? }
    public static func permissionValue(in text: String, layout: Layout) -> String? {
        guard let (value, _) = try? locate(text, layout: layout), let value else { return nil }
        return value.nativeMode ?? (value.enabled ? "true" : "false")
    }
    static func locate(_ text: String, layout: Layout = .legacyPython) throws -> (Value?, Int) {
        let bytes = Array(text.utf8)
        let key = layout == .nativeV2 ? "default_permission_mode" : "default_yolo"
        let statements = try TomlPolicyLocator.statements(in: text)
        var root = true, found: Value?, insertion = bytes.count
        for statement in statements {
            switch statement.kind {
            case .table(let path, _):
                if path.first == key { throw ParseFailure.invalid }
                if root { insertion = statement.range.lowerBound }; root = false
            case .assignment(let path) where root && path.first == key && path.count != 1:
                throw ParseFailure.invalid
            case .assignment(let path) where root && path == [key]:
                guard found == nil, let equal = bytes[statement.range].firstIndex(of: 0x3D) else { throw ParseFailure.invalid }
                var start = equal + 1
                while start < statement.range.upperBound && [9, 32].contains(bytes[start]) { start += 1 }
                var end = start
                while end < statement.range.upperBound && ![10, 13, 35].contains(bytes[end]) { end += 1 }
                var trimmedEnd = end
                while trimmedEnd > start && [9, 32].contains(bytes[trimmedEnd - 1]) { trimmedEnd -= 1 }
                let token = String(decoding: bytes[start..<trimmedEnd], as: UTF8.self)
                let enabled: Bool
                if layout == .legacyPython {
                    guard token == "true" || token == "false" else { throw ParseFailure.invalid }
                    enabled = token == "true"
                } else {
                    guard ["\"manual\"", "'manual'", "\"yolo\"", "'yolo'", "\"auto\"", "'auto'"].contains(token) else { throw ParseFailure.invalid }
                    enabled = token != "\"manual\"" && token != "'manual'"
                }
                let comment = String(decoding: bytes[end..<statement.range.upperBound], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                found = Value(range: start..<trimmedEnd, enabled: enabled, legacyOwned: layout == .legacyPython && comment.hasPrefix("# AhaKey: dial auto;"),
                    nativeMode: layout == .nativeV2 ? String(token.dropFirst().dropLast()) : nil)
            default: break
            }
        }
        return (found, insertion)
    }
    enum ParseFailure: Error { case invalid }
    private static func update(auto: Bool, configURL: URL, layout: Layout) -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: configURL), let text = String(data: data, encoding: .utf8),
              let (value, insertion) = try? locate(text, layout: layout) else { return .invalid }
        if value?.enabled == auto {
            if !auto { try? fm.removeItem(at: leaseURL(configURL)) }
            return .unchanged
        }
        if auto {
            do { try Data([layout == .nativeV2 ? 2 : 1]).write(to: leaseURL(configURL), options: .atomic) } catch { return .writeFailed }
        }
        let token = layout == .legacyPython ? (auto ? "true" : "false") : (auto ? "\"yolo\"" : "\"manual\"")
        let key = layout == .legacyPython ? "default_yolo" : "default_permission_mode"
        var bytes = Array(data)
        if let value { bytes.replaceSubrange(value.range, with: Array(token.utf8)) }
        else {
            let newline = text.contains("\r\n") ? "\r\n" : (text.contains("\r") ? "\r" : "\n")
            let before = insertion > 0 && ![10,13].contains(bytes[insertion - 1]) ? newline : ""
            bytes.insert(contentsOf: Array((before + key + " = " + token + newline).utf8), at: insertion)
        }
        do {
            try Data(bytes).write(to: configURL, options: .atomic)
            if !auto { try? fm.removeItem(at: leaseURL(configURL)) }
            return .updated
        } catch { return .writeFailed }
    }
    static func releaseOwnedAutomation(configURL: URL) -> Outcome {
        if FileManager.default.fileExists(atPath: KimiManagedPermissionDefaults.journalURL(configURL).path) {
            switch KimiManagedPermissionDefaults.restoreUnlocked(configURL: configURL) {
            case .restored: return .updated
            case .userOverride, .unmanaged: return .notOwned
            case .missing: return .missing
            case .writeFailed: return .writeFailed
            default: return .invalid
            }
        }
        guard let data = try? Data(contentsOf: configURL), let text = String(data: data, encoding: .utf8) else {
            if FileManager.default.fileExists(atPath: configURL.path) { return .invalid }
            try? FileManager.default.removeItem(at: leaseURL(configURL))
            return .missing
        }
        let lease = try? Data(contentsOf: leaseURL(configURL))
        if FileManager.default.fileExists(atPath: leaseURL(configURL).path), lease == nil { return .invalid }
        if let lease, lease != Data([1]), lease != Data([2]) { return .invalid }
        if lease == nil, !text.contains("# AhaKey: dial auto;") { return .notOwned }
        let layout: Layout = lease == Data([2]) ? .nativeV2 : .legacyPython
        guard let (value, _) = try? locate(text, layout: layout) else { return .invalid }
        guard FileManager.default.fileExists(atPath: leaseURL(configURL).path) || value?.legacyOwned == true else { return .notOwned }
        if layout == .nativeV2, value?.nativeMode == "auto" {
            // We write yolo, never native Never Ask. A later user change is
            // outside this lease and must survive uninstall/background stop.
            try? FileManager.default.removeItem(at: leaseURL(configURL))
            return .notOwned
        }
        if value?.enabled == true { return update(auto: false, configURL: configURL, layout: layout) }
        try? FileManager.default.removeItem(at: leaseURL(configURL))
        return .unchanged
    }
}
