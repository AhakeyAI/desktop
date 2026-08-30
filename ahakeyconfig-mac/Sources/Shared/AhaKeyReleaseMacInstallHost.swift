import Darwin
import Foundation
import ServiceManagement

public struct AhaKeyReleaseCodeSignature: Equatable, Sendable {
    public var signatureKind: AhaKeyReleaseSignatureKind
    public var teamIdentifier: String?
    public var signingIdentifier: String?

    public init(
        signatureKind: AhaKeyReleaseSignatureKind,
        teamIdentifier: String?,
        signingIdentifier: String?
    ) {
        self.signatureKind = signatureKind
        self.teamIdentifier = teamIdentifier
        self.signingIdentifier = signingIdentifier
    }
}

public protocol AhaKeyReleaseProcessRunning: AnyObject {
    func run(executable: String, arguments: [String]) throws -> (status: Int32, output: String)
}

public final class AhaKeyReleasePosixProcessRunner: AhaKeyReleaseProcessRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

public final class AhaKeyReleaseRecordingProcessRunner: AhaKeyReleaseProcessRunning {
    public var calls: [[String]] = []
    public var statusByJoinedArguments: [String: Int32] = [:]
    public var outputByJoinedArguments: [String: String] = [:]
    public var defaultStatus: Int32 = 0
    public var defaultOutput = ""

    public init() {}

    public func run(executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        _ = executable
        calls.append(arguments)
        let key = arguments.joined(separator: " ")
        let status = statusByJoinedArguments[key] ?? defaultStatus
        let output = outputByJoinedArguments[key] ?? defaultOutput
        return (status, output)
    }
}

/// launchd / 登录项 / codesign 检查缝。生产适配器会改系统；测试注入 Recording 适配器。
public protocol AhaKeyReleaseSystemControl: AnyObject {
    func darwinMajor() -> Int
    func loadedLaunchdLabels() throws -> Set<String>
    var loginItemRegistered: Bool { get }
    func bootout(label: String) throws
    func bootstrap(label: String, plistPath: String) throws
    func registerLoginItem() throws
    func unregisterLoginItem() throws
    func inspectCodeSignature(at path: String) throws -> AhaKeyReleaseCodeSignature
    func verifyCodeSignature(at path: String) throws
}

public final class AhaKeyReleaseRecordingSystemControl: AhaKeyReleaseSystemControl {
    public var darwinMajorValue: Int
    public var loaded: Set<String>
    public var loginItemRegistered: Bool
    public var signatures: [String: AhaKeyReleaseCodeSignature]
    public var useProcessCodesign: Bool
    public var bootoutError: AhaKeyReleaseInstallError?
    public var bootstrapError: AhaKeyReleaseInstallError?
    public var failingVerify: Set<String> = []
    public var failingVerifyIfPathContains: String?

    public init(
        darwinMajorValue: Int = 22,
        loaded: Set<String> = [],
        loginItemRegistered: Bool = false,
        signatures: [String: AhaKeyReleaseCodeSignature] = [:],
        useProcessCodesign: Bool = false
    ) {
        self.darwinMajorValue = darwinMajorValue
        self.loaded = loaded
        self.loginItemRegistered = loginItemRegistered
        self.signatures = signatures
        self.useProcessCodesign = useProcessCodesign
    }

    public func darwinMajor() -> Int { darwinMajorValue }

    public func loadedLaunchdLabels() throws -> Set<String> { loaded }

    public func bootout(label: String) throws {
        if let bootoutError {
            throw bootoutError
        }
        loaded.remove(label)
    }

    public func bootstrap(label: String, plistPath: String) throws {
        if let bootstrapError {
            throw bootstrapError
        }
        _ = plistPath
        loaded.insert(label)
    }

    public func registerLoginItem() throws {
        loginItemRegistered = true
    }

    public func unregisterLoginItem() throws {
        loginItemRegistered = false
    }

    public func inspectCodeSignature(at path: String) throws -> AhaKeyReleaseCodeSignature {
        if let injected = signatures[path] {
            return injected
        }
        if useProcessCodesign {
            return try AhaKeyReleaseCodesignInspector.inspect(at: path)
        }
        throw AhaKeyReleaseInstallError.hostFailure("no signature for \(path)")
    }

    public func verifyCodeSignature(at path: String) throws {
        if failingVerify.contains(path) {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.appIntegrityFailed))
        }
        if let needle = failingVerifyIfPathContains, path.contains(needle) {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.appIntegrityFailed))
        }
        if useProcessCodesign {
            try AhaKeyReleaseCodesignInspector.verifyStrict(at: path)
            return
        }
        if signatures[path] == nil {
            throw AhaKeyReleaseInstallError.hostFailure("no signature for \(path)")
        }
    }
}

/// 真实 launchctl + SMAppService。默认拒绝系统突变；HIL 才能把 `allowSystemMutation` 打开。
/// `loadedLaunchdLabels` / login-item status 是只读查询，不要求 mutation 开关。
public final class AhaKeyReleaseLaunchdControl: AhaKeyReleaseSystemControl {
    public var allowSystemMutation: Bool
    private let process: AhaKeyReleaseProcessRunning
    private let identity: AhaKeyReleaseIdentity

    public init(
        allowSystemMutation: Bool = false,
        process: AhaKeyReleaseProcessRunning = AhaKeyReleasePosixProcessRunner(),
        identity: AhaKeyReleaseIdentity = .current
    ) {
        self.allowSystemMutation = allowSystemMutation
        self.process = process
        self.identity = identity
    }

    public func darwinMajor() -> Int {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion + 9
    }

    public var loginItemRegistered: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    public func loadedLaunchdLabels() throws -> Set<String> {
        let result = try process.run(executable: "/bin/launchctl", arguments: ["list"])
        if result.status != 0 {
            throw AhaKeyReleaseInstallError.hostFailure("launchctl list exit \(result.status): \(result.output)")
        }
        var loaded: Set<String> = []
        for raw in result.output.split(whereSeparator: \.isNewline) {
            let parts = raw.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let label = parts.last, identity.isAhaKeyLaunchdLabel(label) else { continue }
            loaded.insert(label)
        }
        for label in [identity.agentLaunchdLabel, identity.hilLaunchdLabel] {
            let printResult = try process.run(
                executable: "/bin/launchctl",
                arguments: ["print", guiTarget(label)]
            )
            if printResult.status == 0 {
                loaded.insert(label)
                continue
            }
            if Self.isServiceNotFound(status: printResult.status, output: printResult.output, label: label) {
                continue
            }
            throw AhaKeyReleaseInstallError.hostFailure(
                "launchctl print \(guiTarget(label)) exit \(printResult.status): \(printResult.output)"
            )
        }
        return loaded
    }

    public static let serviceNotFoundStatus: Int32 = 113

    public static func isServiceNotFound(status: Int32, output: String, label: String) -> Bool {
        guard status == serviceNotFoundStatus else { return false }
        let needle = "Could not find service \"\(label)\""
        return output.split(whereSeparator: \.isNewline).contains { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix(needle)
        }
    }

    public func bootout(label: String) throws {
        try requireMutation()
        try runLaunchctlChecked(["bootout", guiTarget(label)])
    }

    public func bootstrap(label: String, plistPath: String) throws {
        try requireMutation()
        _ = label
        try runLaunchctlChecked(["bootstrap", "gui/\(getuid())", plistPath])
    }

    public func registerLoginItem() throws {
        try requireMutation()
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.register()
        } else {
            throw AhaKeyReleaseInstallError.rejected(.unsupportedMacOS(darwinMajor: darwinMajor()))
        }
    }

    public func unregisterLoginItem() throws {
        try requireMutation()
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.unregister()
        }
    }

    public func inspectCodeSignature(at path: String) throws -> AhaKeyReleaseCodeSignature {
        try AhaKeyReleaseCodesignInspector.inspect(at: path)
    }

    public func verifyCodeSignature(at path: String) throws {
        try AhaKeyReleaseCodesignInspector.verifyStrict(at: path)
    }

    private func requireMutation() throws {
        if !allowSystemMutation {
            throw AhaKeyReleaseInstallError.rejected(.systemMutationNotAllowed)
        }
    }

    private func guiTarget(_ label: String) -> String {
        "gui/\(getuid())/\(label)"
    }

    private func runLaunchctlChecked(_ arguments: [String]) throws {
        let result = try process.run(executable: "/bin/launchctl", arguments: arguments)
        if result.status != 0 {
            throw AhaKeyReleaseInstallError.hostFailure(
                "launchctl \(arguments.joined(separator: " ")) exit \(result.status): \(result.output)"
            )
        }
    }
}

public enum AhaKeyReleaseCodesignInspector {
    public static func verifyStrict(at path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", "--verbose=2", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AhaKeyReleaseInstallError.hostFailure("codesign --verify --strict failed for \(path): \(output)")
        }
    }

    public static func inspect(at path: String) throws -> AhaKeyReleaseCodeSignature {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            return AhaKeyReleaseCodeSignature(signatureKind: .unknown, teamIdentifier: nil, signingIdentifier: nil)
        }
        var identifier: String?
        var team: String?
        var kind: AhaKeyReleaseSignatureKind = .unknown
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("Identifier=") {
                identifier = String(text.dropFirst("Identifier=".count))
            } else if text.hasPrefix("TeamIdentifier=") {
                let value = String(text.dropFirst("TeamIdentifier=".count))
                if value != "not set" && value != "-" {
                    team = value
                }
            } else if text.hasPrefix("Authority=") {
                let authority = String(text.dropFirst("Authority=".count))
                if authority == "adhoc" || authority.hasPrefix("-") {
                    kind = .adhoc
                } else if authority.hasPrefix("Developer ID Application") {
                    kind = .developerID
                }
            }
        }
        if kind == .unknown, team == nil, identifier != nil {
            kind = .adhoc
        }
        return AhaKeyReleaseCodeSignature(
            signatureKind: kind,
            teamIdentifier: team,
            signingIdentifier: identifier
        )
    }
}

public enum AhaKeyReleaseWriteFailurePoint: Equatable, Sendable {
    case afterExclusiveCreate
    case afterWrite
    case afterFsync
    case afterRename
    case afterDirectoryFsync
    case afterFinalFsync
}

public enum AhaKeyReleaseAtomicFile {
    public static func write(
        to path: String,
        data: Data,
        isSymlink: (String) -> Bool,
        failAt: AhaKeyReleaseWriteFailurePoint? = nil
    ) throws {
        if isSymlink(path) {
            throw AhaKeyReleaseInstallError.pathViolation(.pathContainsSymlink(path))
        }
        let directory = (path as NSString).deletingLastPathComponent
        if isSymlink(directory) {
            throw AhaKeyReleaseInstallError.pathViolation(.pathContainsSymlink(directory))
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var fd: Int32 = -1
        var temp = ""
        for _ in 0..<8 {
            temp = (directory as NSString).appendingPathComponent(".ahakey-\(UUID().uuidString).tmp")
            fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
            if fd >= 0 { break }
            if errno != EEXIST {
                throw AhaKeyReleaseInstallError.hostFailure("exclusive create failed errno=\(errno)")
            }
        }
        guard fd >= 0 else {
            throw AhaKeyReleaseInstallError.hostFailure("exclusive temp create exhausted")
        }

        func abandonTemp() {
            if fd >= 0 {
                close(fd)
                fd = -1
            }
            unlink(temp)
        }

        if failAt == .afterExclusiveCreate {
            abandonTemp()
            throw AhaKeyReleaseInstallError.hostFailure("injected afterExclusiveCreate")
        }

        let written: Int = data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return Darwin.write(fd, base, data.count)
        }
        if written != data.count {
            abandonTemp()
            throw AhaKeyReleaseInstallError.hostFailure("short write to \(temp)")
        }
        if failAt == .afterWrite {
            abandonTemp()
            throw AhaKeyReleaseInstallError.hostFailure("injected afterWrite")
        }
        if fcntl(fd, F_FULLFSYNC) == -1, fsync(fd) != 0 {
            abandonTemp()
            throw AhaKeyReleaseInstallError.hostFailure("fsync temp failed: \(temp)")
        }
        if failAt == .afterFsync {
            abandonTemp()
            throw AhaKeyReleaseInstallError.hostFailure("injected afterFsync")
        }
        close(fd)
        fd = -1

        var previousBackup: String?
        let destExisted = FileManager.default.fileExists(atPath: path) && !isSymlink(path)
        if destExisted {
            previousBackup = (directory as NSString).appendingPathComponent(".ahakey-prev-\(UUID().uuidString).tmp")
            do {
                try preserveExistingFile(at: path, to: previousBackup!)
            } catch {
                unlink(temp)
                throw error
            }
        }

        if rename(temp, path) != 0 {
            let saved = errno
            unlink(temp)
            if let previousBackup { unlink(previousBackup) }
            throw AhaKeyReleaseInstallError.hostFailure("rename \(temp) → \(path) errno=\(saved)")
        }

        do {
            if failAt == .afterRename {
                throw AhaKeyReleaseInstallError.hostFailure("injected afterRename")
            }
            try AhaKeyReleaseDiskSync.fsyncDirectory(at: directory)
            if failAt == .afterDirectoryFsync {
                throw AhaKeyReleaseInstallError.hostFailure("injected afterDirectoryFsync")
            }
            try AhaKeyReleaseDiskSync.fsyncItem(at: path)
            if failAt == .afterFinalFsync {
                throw AhaKeyReleaseInstallError.hostFailure("injected afterFinalFsync")
            }
        } catch {
            do {
                try restorePreviousFile(at: path, previousBackup: previousBackup, directory: directory)
            } catch {
                throw AhaKeyReleaseInstallError.rollbackFailed(
                    "plist post-rename restore failed: \(error)"
                )
            }
            throw error
        }
        if let previousBackup {
            unlink(previousBackup)
        }
    }

    private static func preserveExistingFile(at path: String, to backup: String) throws {
        let fd = open(backup, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard fd >= 0 else {
            throw AhaKeyReleaseInstallError.hostFailure("exclusive previous backup failed errno=\(errno)")
        }
        defer { close(fd) }
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
        let written: Int = data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return Darwin.write(fd, base, data.count)
        }
        if written != data.count {
            unlink(backup)
            throw AhaKeyReleaseInstallError.hostFailure("short write preserving \(path)")
        }
        if fcntl(fd, F_FULLFSYNC) == -1, fsync(fd) != 0 {
            unlink(backup)
            throw AhaKeyReleaseInstallError.hostFailure("fsync previous backup failed")
        }
    }

    private static func restorePreviousFile(at path: String, previousBackup: String?, directory: String) throws {
        if let previousBackup {
            if rename(previousBackup, path) != 0 {
                let saved = errno
                throw AhaKeyReleaseInstallError.hostFailure("restore rename errno=\(saved)")
            }
            try AhaKeyReleaseDiskSync.fsyncItem(at: path)
            try AhaKeyReleaseDiskSync.fsyncDirectory(at: directory)
            return
        }
        unlink(path)
        try AhaKeyReleaseDiskSync.fsyncDirectory(at: directory)
    }
}

public enum AhaKeyReleaseDiskSync {
    public static func fsyncItem(at path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else {
            throw AhaKeyReleaseInstallError.hostFailure("open for fsync failed: \(path)")
        }
        defer { close(fd) }
        if fcntl(fd, F_FULLFSYNC) == -1 {
            if fsync(fd) != 0 {
                throw AhaKeyReleaseInstallError.hostFailure("fsync failed: \(path)")
            }
        }
    }

    public static func fsyncDirectory(at path: String) throws {
        try fsyncItem(at: path)
    }
}

/// rename/replace 已提交后，将真实 fsync/清理错误统一转为 mutation receipt。
public enum AhaKeyReleaseMutationBoundary {
    public static func afterCommit(_ work: () throws -> Void) throws {
        do {
            try work()
        } catch {
            if case .failedAfterAppMutation = error as? AhaKeyReleaseInstallError {
                throw error
            }
            throw AhaKeyReleaseInstallError.failedAfterAppMutation(String(describing: error))
        }
    }
}

/// 生产安装 host：真实文件原子替换 + 可注入的 launchd/登录项。
/// 本卡只允许沙箱 layout + Recording 系统控制；不得对 `/Applications` 或真实 LaunchAgents 调用。
public final class AhaKeyReleaseMacInstallHost: AhaKeyReleaseInstallHost {
    private let fileManager: FileManager
    private let system: AhaKeyReleaseSystemControl
    public var injectedDirectoryFsyncError: AhaKeyReleaseInstallError?
    public var injectedWriteFailure: AhaKeyReleaseWriteFailurePoint?

    public init(fileManager: FileManager = .default, system: AhaKeyReleaseSystemControl) {
        self.fileManager = fileManager
        self.system = system
    }

    /// HIL 可调用的生产 host。默认禁止系统突变。
    public static func production(allowSystemMutation: Bool = false) -> AhaKeyReleaseMacInstallHost {
        AhaKeyReleaseMacInstallHost(system: AhaKeyReleaseLaunchdControl(allowSystemMutation: allowSystemMutation))
    }

    public func snapshot(layout: AhaKeyReleaseInstallLayout) throws -> AhaKeyReleaseHostSnapshot {
        var exists: [String: Bool] = [:]
        for path in layout.preservedPaths {
            exists[path] = fileManager.fileExists(atPath: path)
        }
        return AhaKeyReleaseHostSnapshot(
            darwinMajor: system.darwinMajor(),
            appInstalled: fileManager.fileExists(atPath: layout.applicationsAppPath),
            loadedLaunchdLabels: try system.loadedLaunchdLabels(),
            loginItemRegistered: system.loginItemRegistered,
            preservedPathExists: exists
        )
    }

    public func inspectCandidate(at appPath: String, identity: AhaKeyReleaseIdentity) throws -> AhaKeyReleaseCandidateReport {
        let info = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: info)
        let plist = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil)
        let dict = plist as? [String: Any]
        let bundleID = dict?["CFBundleIdentifier"] as? String
        let agent = identity.agentBinaryPath(inApp: appPath)
        var isDir: ObjCBool = false
        let agentPresent = fileManager.fileExists(atPath: agent, isDirectory: &isDir) && !isDir.boolValue
        let companion = URL(fileURLWithPath: appPath)
            .deletingLastPathComponent()
            .appendingPathComponent("LaunchAgent.plist")
        let launchPlist = try? Data(contentsOf: companion)
        var appIntegrity = false
        var agentIntegrity = false
        if agentPresent {
            do {
                try system.verifyCodeSignature(at: appPath)
                appIntegrity = true
            } catch {
                appIntegrity = false
            }
            do {
                try system.verifyCodeSignature(at: agent)
                agentIntegrity = true
            } catch {
                agentIntegrity = false
            }
        }
        let appSignature = try system.inspectCodeSignature(at: appPath)
        let agentSignature = agentPresent ? try system.inspectCodeSignature(at: agent) : AhaKeyReleaseCodeSignature(
            signatureKind: .unknown,
            teamIdentifier: nil,
            signingIdentifier: nil
        )
        return AhaKeyReleaseCandidateReport(
            bundleIdentifier: bundleID,
            agentBinaryPresent: agentPresent,
            launchAgentPlist: launchPlist,
            teamIdentifier: appSignature.teamIdentifier,
            signingIdentifier: appSignature.signingIdentifier,
            signatureKind: appSignature.signatureKind,
            appIntegrityVerified: appIntegrity,
            agentIntegrityVerified: agentIntegrity,
            agentSigningIdentifier: agentSignature.signingIdentifier,
            agentTeamIdentifier: agentSignature.teamIdentifier,
            agentSignatureKind: agentSignature.signatureKind
        )
    }

    public func itemExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    public func isSymlink(_ path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    public func resolvedPath(_ path: String) -> String? {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    public func replaceDirectoryAtomically(from: String, to: String, backup: String, staging: String) throws {
        if fileManager.fileExists(atPath: staging) {
            throw AhaKeyReleaseInstallError.pathViolation(.stagingAlreadyExists(staging))
        }
        if fileManager.fileExists(atPath: backup) {
            throw AhaKeyReleaseInstallError.pathViolation(.backupAlreadyExists(backup))
        }
        let destParent = (to as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: destParent, withIntermediateDirectories: true)
        try fileManager.copyItem(atPath: from, toPath: staging)
        try AhaKeyReleaseDiskSync.fsyncDirectory(at: destParent)
        try fsyncTree(staging)
        do {
            try verifyStagedApp(staging)
        } catch {
            try? fileManager.removeItem(atPath: staging)
            throw error
        }
        let destURL = URL(fileURLWithPath: to)
        let stagingURL = URL(fileURLWithPath: staging)
        if fileManager.fileExists(atPath: to) {
            let backupName = URL(fileURLWithPath: backup).lastPathComponent
            _ = try fileManager.replaceItemAt(
                destURL,
                withItemAt: stagingURL,
                backupItemName: backupName,
                options: .withoutDeletingBackupItem
            )
        } else {
            try renameAtomically(from: staging, to: to)
        }
        try AhaKeyReleaseMutationBoundary.afterCommit {
            if let injected = injectedDirectoryFsyncError {
                injectedDirectoryFsyncError = nil
                throw injected
            }
            try AhaKeyReleaseDiskSync.fsyncDirectory(at: destParent)
            if fileManager.fileExists(atPath: staging) {
                try fileManager.removeItem(atPath: staging)
            }
        }
    }

    public func moveDirectoryAtomically(from: String, to: String) throws {
        if fileManager.fileExists(atPath: to) {
            throw AhaKeyReleaseInstallError.pathViolation(.backupAlreadyExists(to))
        }
        let destParent = (to as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: destParent, withIntermediateDirectories: true)
        try renameAtomically(from: from, to: to)
        try AhaKeyReleaseMutationBoundary.afterCommit {
            if let injected = injectedDirectoryFsyncError {
                injectedDirectoryFsyncError = nil
                throw injected
            }
            try AhaKeyReleaseDiskSync.fsyncDirectory(at: destParent)
        }
    }

    public func removeTree(_ path: String) throws {
        if fileManager.fileExists(atPath: path) {
            let parent = (path as NSString).deletingLastPathComponent
            try fileManager.removeItem(atPath: path)
            try AhaKeyReleaseDiskSync.fsyncDirectory(at: parent)
        }
    }

    public func writeFile(at path: String, data: Data) throws {
        let failAt = injectedWriteFailure
        injectedWriteFailure = nil
        try AhaKeyReleaseAtomicFile.write(
            to: path,
            data: data,
            isSymlink: isSymlink,
            failAt: failAt
        )
    }

    public func readFile(at path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    public func bootout(label: String) throws {
        try system.bootout(label: label)
    }

    public func bootstrap(label: String, plistPath: String) throws {
        try system.bootstrap(label: label, plistPath: plistPath)
    }

    public func registerLoginItem() throws {
        try system.registerLoginItem()
    }

    public func unregisterLoginItem() throws {
        try system.unregisterLoginItem()
    }

    private func verifyStagedApp(_ staging: String) throws {
        let identity = AhaKeyReleaseIdentity.current
        let info = URL(fileURLWithPath: staging).appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: info)
        let plist = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil)
        let bundleID = (plist as? [String: Any])?["CFBundleIdentifier"] as? String
        guard bundleID == identity.bundleIdentifier else {
            throw AhaKeyReleaseInstallError.rejected(
                .identityRejected(.bundleIdentifierMismatch(found: bundleID ?? ""))
            )
        }
        let agent = identity.agentBinaryPath(inApp: staging)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: agent, isDirectory: &isDir), !isDir.boolValue else {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.missingAgentBinary))
        }
        do {
            try system.verifyCodeSignature(at: staging)
        } catch {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.appIntegrityFailed))
        }
        do {
            try system.verifyCodeSignature(at: agent)
        } catch {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.agentIntegrityFailed))
        }
        let appSignature = try system.inspectCodeSignature(at: staging)
        let agentSignature = try system.inspectCodeSignature(at: agent)
        let report = AhaKeyReleaseCandidateReport(
            bundleIdentifier: bundleID,
            agentBinaryPresent: true,
            launchAgentPlist: try identity.launchAgentPlist(
                agentBinaryPath: agent,
                socketPath: "/tmp/ahakey-staging.sock",
                logPath: "/tmp/ahakey-staging.log"
            ),
            teamIdentifier: appSignature.teamIdentifier,
            signingIdentifier: appSignature.signingIdentifier,
            signatureKind: appSignature.signatureKind,
            appIntegrityVerified: true,
            agentIntegrityVerified: true,
            agentSigningIdentifier: agentSignature.signingIdentifier,
            agentTeamIdentifier: agentSignature.teamIdentifier,
            agentSignatureKind: agentSignature.signatureKind
        )
        if case .rejected(let reason) = AhaKeyReleaseSigningChecklist.check(report, identity: identity) {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(reason))
        }
    }

    private func fsyncTree(_ root: String) throws {
        let enumerator = fileManager.enumerator(atPath: root)
        while let relative = enumerator?.nextObject() as? String {
            let full = (root as NSString).appendingPathComponent(relative)
            try AhaKeyReleaseDiskSync.fsyncItem(at: full)
        }
        try AhaKeyReleaseDiskSync.fsyncDirectory(at: root)
    }

    private func renameAtomically(from: String, to: String) throws {
        if rename(from, to) != 0 {
            throw AhaKeyReleaseInstallError.hostFailure("rename \(from) → \(to) errno=\(errno)")
        }
    }
}

extension AhaKeyReleaseInstaller {
    /// 产品/HIL 入口：生产 host + 生产布局。本卡不得把 `allowSystemMutation` 打开。
    public static func productionHost(allowSystemMutation: Bool = false) -> AhaKeyReleaseMacInstallHost {
        .production(allowSystemMutation: allowSystemMutation)
    }
}
