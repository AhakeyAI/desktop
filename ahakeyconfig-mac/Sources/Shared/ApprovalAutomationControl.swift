import Foundation
import Darwin

/// A shared lock serializes in-flight policy writes with stop/remove revocation.
public enum ApprovalAutomationControl {
    public enum Client: String, CaseIterable { case claude, cursor, codex, kimi }
    public static var productionDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AhaKeyConfig/approval-control", isDirectory: true)
    }
    static func locked<T>(directory: URL, _ body: () -> T) -> T? {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { return nil }
        let fd = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return nil }
        defer { flock(fd, LOCK_UN) }
        return body()
    }
    static func enabledUnlocked(_ client: Client?, directory: URL) -> Bool {
        let fm = FileManager.default
        return !fm.fileExists(atPath: directory.appendingPathComponent("all.paused").path) &&
            (client.map { !fm.fileExists(atPath: directory.appendingPathComponent($0.rawValue + ".paused").path) } ?? true)
    }
    public static func isEnabled(_ client: Client? = nil, directory: URL = productionDirectory) -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: directory.path) }
        catch let error as NSError {
            return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
        }
        return locked(directory: directory) { enabledUnlocked(client, directory: directory) } ?? false
    }
    @discardableResult
    public static func resume(_ client: Client? = nil, directory: URL = productionDirectory) -> Bool {
        locked(directory: directory) {
            let path = directory.appendingPathComponent(client.map { $0.rawValue + ".paused" } ?? "all.paused")
            if !FileManager.default.fileExists(atPath: path.path) { return true }
            do { try FileManager.default.removeItem(at: path); return true } catch { return false }
        } ?? false
    }
    /// Revoke first, while holding the same lock as policy writers, then clean
    /// owned auto values. No full-file snapshot restoration.
    @discardableResult
    public static func revoke(_ client: Client? = nil, directory: URL = productionDirectory,
                              codexURL: URL = CodexConfigLeverSync.productionConfigURL,
                              kimiURL: URL = KimiConfigPolicySync.productionConfigURL,
                              cursorDirectory: URL = CursorApprovalPolicySync.productionDirectory) -> Bool {
        let legacyCleanup = locked(directory: directory) {
            let path = directory.appendingPathComponent(client.map { $0.rawValue + ".paused" } ?? "all.paused")
            do { try Data([1]).write(to: path, options: .atomic) } catch { return false }
            var success = true
            if client == nil || client == .cursor { success = CursorApprovalPolicySync.releaseAll(directory: cursorDirectory) }
            if client == nil || client == .codex {
                switch CodexConfigLeverSync.releaseOwnedAutomation(configURL: codexURL) {
                case .writeFailed, .unreadableConfig, .duplicateKey, .unsupportedSyntax: success = false
                default: break
                }
            }
            if client == nil || client == .kimi {
                let registered = KimiConfigPolicySync.ownedConfigURLs(directory: directory)
                if registered == nil { success = false }
                var urls = Set((registered ?? []) + [kimiURL])
                if directory == productionDirectory {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    urls.insert(home.appendingPathComponent(".kimi/config.toml"))
                    urls.insert(home.appendingPathComponent(".kimi-code/config.toml"))
                }
                for url in urls {
                    switch KimiConfigPolicySync.releaseOwnedAutomation(configURL: url) {
                    case .invalid, .writeFailed: success = false
                    default:
                        if !KimiConfigPolicySync.record(url, owned: false, directory: directory) { success = false }
                    }
                }
            }
            return success
        } ?? false
        guard legacyCleanup else { return false }
        // The daemon reconciles native sessions asynchronously after seeing the
        // pause. Do not report complete revocation while its recovery journal
        // still owns permissions, or recurse into the same file lock above.
        if client == nil || client == .codex {
            return (try? CodexDesktopLeverState(directory: directory).hasPendingRecovery()) == false
        }
        return true
    }
}
