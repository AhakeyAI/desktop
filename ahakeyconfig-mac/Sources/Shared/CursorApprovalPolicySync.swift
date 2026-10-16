import Foundation

/// Owns only the permission tokens AhaKey adds. Never restores a whole config snapshot.
public enum CursorApprovalPolicySync {
    public enum Kind { case cli, desktop }
    public static var productionDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor") }
    private struct Lease: Codable {
        var added: [String]
        var changedMode: Bool
        var previousMode: String?
    }
    private static func url(_ kind: Kind, _ directory: URL) -> URL {
        directory.appendingPathComponent(kind == .cli ? "cli-config.json" : "permissions.json")
    }
    private static func tokens(_ kind: Kind) -> [String] {
        kind == .desktop ? ["*"] : ["Shell(*)", "Shell(cd)", "Shell(swift)", "Shell(bash)", "Shell(zsh)", "Shell(sh)", "Read(**/*)", "Write(**/*)", "WebFetch(*)", "Mcp(*:*)"]
    }
    private static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let root = object as? [String: Any] else { throw Failure.invalid }
        return root
    }
    private enum Failure: Error { case invalid }
    private static func list(_ root: [String: Any], _ kind: Kind) throws -> [String] {
        let value: Any?
        if kind == .desktop { value = root["terminalAllowlist"] }
        else {
            if let permissions = root["permissions"], !(permissions is [String: Any]) { throw Failure.invalid }
            value = (root["permissions"] as? [String: Any])?["allow"]
        }
        guard let value else { return [] }
        guard let strings = value as? [String] else { throw Failure.invalid }
        return strings
    }
    private static func setList(_ value: [String], root: inout [String: Any], kind: Kind) {
        if kind == .desktop { root["terminalAllowlist"] = value }
        else { var permissions = root["permissions"] as? [String: Any] ?? [:]; permissions["allow"] = value; root["permissions"] = permissions }
    }
    private static func write(_ root: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    @discardableResult
    public static func apply(auto: Bool, kind: Kind, directory: URL = productionDirectory,
                             controlDirectory: URL = ApprovalAutomationControl.productionDirectory) -> Bool {
        ApprovalAutomationControl.locked(directory: controlDirectory) {
            if auto && !ApprovalAutomationControl.enabledUnlocked(.cursor, directory: controlDirectory) { return false }
            do {
                try releaseLegacy(kind, directory: directory)
                if !auto { try release(kind, directory: directory); return true }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = url(kind, directory), leaseURL = target.appendingPathExtension("ahakey-auto-lease")
                var root = try read(target)
                let current = try list(root, kind)
                var lease = FileManager.default.fileExists(atPath: leaseURL.path)
                    ? try JSONDecoder().decode(Lease.self, from: Data(contentsOf: leaseURL))
                    : Lease(added: [], changedMode: false, previousMode: nil)
                let added = tokens(kind).filter { !current.contains($0) }
                for token in added where !lease.added.contains(token) { lease.added.append(token) }
                if kind == .cli, root["approvalMode"] as? String != "auto" {
                    if let mode = root["approvalMode"], !(mode is String) { throw Failure.invalid }
                    if !lease.changedMode { lease.previousMode = root["approvalMode"] as? String }
                    lease.changedMode = true
                    root["approvalMode"] = "auto"
                }
                guard !added.isEmpty || lease.changedMode else { return true }
                // Persist ownership before changing permission values.
                try JSONEncoder().encode(lease).write(to: leaseURL, options: .atomic)
                setList(current + added, root: &root, kind: kind)
                try write(root, to: target)
                return true
            } catch { return false }
        } ?? false
    }
    static func releaseAll(directory: URL = productionDirectory) -> Bool {
        var success = true
        for kind in [Kind.cli, .desktop] {
            do { try releaseLegacy(kind, directory: directory); try release(kind, directory: directory) }
            catch { success = false }
        }
        return success
    }
    private static func release(_ kind: Kind, directory: URL) throws {
        let target = url(kind, directory), leaseURL = target.appendingPathExtension("ahakey-auto-lease")
        guard FileManager.default.fileExists(atPath: leaseURL.path) else { return }
        let lease = try JSONDecoder().decode(Lease.self, from: Data(contentsOf: leaseURL))
        var root = try read(target)
        if FileManager.default.fileExists(atPath: target.path) {
            let current = try list(root, kind)
            setList(current.filter { !lease.added.contains($0) }, root: &root, kind: kind)
            if kind == .cli, lease.changedMode, root["approvalMode"] as? String == "auto" {
                root["approvalMode"] = lease.previousMode
            }
            try write(root, to: target)
        }
        try FileManager.default.removeItem(at: leaseURL)
    }
    /// Old clients used full-file backups. Use them only to identify injected fields;
    /// later user changes in the current file remain authoritative.
    private static func releaseLegacy(_ kind: Kind, directory: URL) throws {
        let fm = FileManager.default, target = url(kind, directory)
        let backup = target.appendingPathExtension("ahakey.lever0.bak")
        let marker = directory.appendingPathComponent(kind == .cli ? ".ahakey_had_no_cli_config" : ".ahakey_had_no_permissions_json")
        guard fm.fileExists(atPath: backup.path) || fm.fileExists(atPath: marker.path) else { return }
        let original = fm.fileExists(atPath: backup.path) ? try read(backup) : [:]
        if fm.fileExists(atPath: target.path) {
            var root = try read(target)
            let previous = try list(original, kind)
            let injected = tokens(kind).filter { !previous.contains($0) }
            setList(try list(root, kind).filter { !injected.contains($0) }, root: &root, kind: kind)
            if kind == .cli, root["approvalMode"] as? String == "auto" { root["approvalMode"] = original["approvalMode"] }
            try write(root, to: target)
        }
        for path in [backup, marker] where fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
    }
}
