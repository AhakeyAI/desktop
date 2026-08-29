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

/// launchd / 登录项 / codesign 检查缝。生产适配器会改系统；测试注入 Recording 适配器。
public protocol AhaKeyReleaseSystemControl: AnyObject {
    func darwinMajor() -> Int
    func loadedLaunchdLabels() -> Set<String>
    var loginItemRegistered: Bool { get }
    func bootout(label: String) throws
    func bootstrap(label: String, plistPath: String) throws
    func registerLoginItem() throws
    func unregisterLoginItem() throws
    func inspectCodeSignature(at path: String) throws -> AhaKeyReleaseCodeSignature
}

public final class AhaKeyReleaseRecordingSystemControl: AhaKeyReleaseSystemControl {
    public var darwinMajorValue: Int
    public var loaded: Set<String>
    public var loginItemRegistered: Bool
    public var signatures: [String: AhaKeyReleaseCodeSignature]
    public var useProcessCodesign: Bool

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

    public func loadedLaunchdLabels() -> Set<String> { loaded }

    public func bootout(label: String) throws {
        loaded.remove(label)
    }

    public func bootstrap(label: String, plistPath: String) throws {
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
}

/// 真实 launchctl + SMAppService。默认拒绝系统突变；HIL 才能把 `allowSystemMutation` 打开。
public final class AhaKeyReleaseLaunchdControl: AhaKeyReleaseSystemControl {
    public var allowSystemMutation: Bool
    public var loginItemRegistered: Bool = false

    public init(allowSystemMutation: Bool = false) {
        self.allowSystemMutation = allowSystemMutation
    }

    public func darwinMajor() -> Int {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion + 9
    }

    public func loadedLaunchdLabels() -> Set<String> {
        []
    }

    public func bootout(label: String) throws {
        try requireMutation()
        _ = try runLaunchctl(["bootout", guiTarget(label)])
    }

    public func bootstrap(label: String, plistPath: String) throws {
        try requireMutation()
        _ = label
        _ = try runLaunchctl(["bootstrap", "gui/\(getuid())", plistPath])
    }

    public func registerLoginItem() throws {
        try requireMutation()
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.register()
            loginItemRegistered = true
        } else {
            throw AhaKeyReleaseInstallError.rejected(.unsupportedMacOS(darwinMajor: darwinMajor()))
        }
    }

    public func unregisterLoginItem() throws {
        try requireMutation()
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.unregister()
            loginItemRegistered = false
        }
    }

    public func inspectCodeSignature(at path: String) throws -> AhaKeyReleaseCodeSignature {
        try AhaKeyReleaseCodesignInspector.inspect(at: path)
    }

    private func requireMutation() throws {
        if !allowSystemMutation {
            throw AhaKeyReleaseInstallError.rejected(.systemMutationNotAllowed)
        }
    }

    private func guiTarget(_ label: String) -> String {
        "gui/\(getuid())/\(label)"
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum AhaKeyReleaseCodesignInspector {
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

/// 生产安装 host：真实文件原子替换 + 可注入的 launchd/登录项。
/// 本卡只允许沙箱 layout + Recording 系统控制；不得对 `/Applications` 或真实 LaunchAgents 调用。
public final class AhaKeyReleaseMacInstallHost: AhaKeyReleaseInstallHost {
    private let fileManager: FileManager
    private let system: AhaKeyReleaseSystemControl

    public init(fileManager: FileManager = .default, system: AhaKeyReleaseSystemControl) {
        self.fileManager = fileManager
        self.system = system
    }

    public func snapshot(layout: AhaKeyReleaseInstallLayout) -> AhaKeyReleaseHostSnapshot {
        var exists: [String: Bool] = [:]
        for path in layout.preservedPaths {
            exists[path] = fileManager.fileExists(atPath: path)
        }
        return AhaKeyReleaseHostSnapshot(
            darwinMajor: system.darwinMajor(),
            appInstalled: fileManager.fileExists(atPath: layout.applicationsAppPath),
            loadedLaunchdLabels: system.loadedLaunchdLabels(),
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
        let signature = try system.inspectCodeSignature(at: appPath)
        return AhaKeyReleaseCandidateReport(
            bundleIdentifier: bundleID,
            agentBinaryPresent: agentPresent,
            launchAgentPlist: launchPlist,
            teamIdentifier: signature.teamIdentifier,
            signingIdentifier: signature.signingIdentifier,
            signatureKind: signature.signatureKind
        )
    }

    public func itemExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    public func isSymlink(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
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
        try verifyStagedApp(staging)
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
        if fileManager.fileExists(atPath: staging) {
            try fileManager.removeItem(atPath: staging)
        }
    }

    public func moveDirectoryAtomically(from: String, to: String) throws {
        if fileManager.fileExists(atPath: to) {
            throw AhaKeyReleaseInstallError.pathViolation(.backupAlreadyExists(to))
        }
        let destParent = (to as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: destParent, withIntermediateDirectories: true)
        try renameAtomically(from: from, to: to)
    }

    public func removeTree(_ path: String) throws {
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }

    public func writeFile(at path: String, data: Data) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let temp = path + ".ahakey-tmp"
        try data.write(to: URL(fileURLWithPath: temp), options: .atomic)
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
        try renameAtomically(from: temp, to: path)
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
        let agent = identity.agentBinaryPath(inApp: staging)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: agent, isDirectory: &isDir), !isDir.boolValue else {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.missingAgentBinary))
        }
    }

    private func renameAtomically(from: String, to: String) throws {
        if rename(from, to) != 0 {
            throw AhaKeyReleaseInstallError.hostFailure("rename \(from) → \(to) errno=\(errno)")
        }
    }
}
