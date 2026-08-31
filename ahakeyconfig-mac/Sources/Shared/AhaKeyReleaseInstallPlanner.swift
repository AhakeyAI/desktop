import CryptoKit
import Foundation

/// 安装器操作的文件系统/launchd 布局。生产指向 `/Applications` 与用户 LaunchAgents；
/// 测试必须注入沙箱路径，不得触碰真实系统目录。
public struct AhaKeyReleaseInstallLayout: Equatable, Sendable {
    public var applicationsAppPath: String
    public var backupAppPath: String
    public var launchAgentsDirectory: String
    public var launchAgentPlistPath: String
    public var logPath: String
    public var socketPath: String
    public var userConfigDirectory: String
    public var hookPaths: [String]
    public var permitsSystemApplicationsInstall: Bool
    public var candidateAllowedRoots: [String]
    /// 由 `.sandboxed` / `.production` 冻结，不得从 backup/staging 等可变字段反推，
    /// 也不得由调用方传入自授权根。
    public let trustedRoots: [String]
    public var stagingAppPath: String
    public var rollbackScratchAppPath: String
    /// 与 host / installer 入口同一份冻结 identity；HIL plist 路径必须由此生成。
    public let identity: AhaKeyReleaseIdentity

    /// 产品调用方不能传入任意 `trustedRoots`；只允许下面两个 factory。
    private init(
        applicationsAppPath: String,
        backupAppPath: String,
        launchAgentsDirectory: String,
        launchAgentPlistPath: String,
        logPath: String,
        socketPath: String,
        userConfigDirectory: String,
        hookPaths: [String],
        permitsSystemApplicationsInstall: Bool = false,
        candidateAllowedRoots: [String] = [],
        trustedRoots: [String],
        stagingAppPath: String,
        rollbackScratchAppPath: String,
        identity: AhaKeyReleaseIdentity
    ) {
        self.applicationsAppPath = applicationsAppPath
        self.backupAppPath = backupAppPath
        self.launchAgentsDirectory = launchAgentsDirectory
        self.launchAgentPlistPath = launchAgentPlistPath
        self.logPath = logPath
        self.socketPath = socketPath
        self.userConfigDirectory = userConfigDirectory
        self.hookPaths = hookPaths
        self.permitsSystemApplicationsInstall = permitsSystemApplicationsInstall
        self.candidateAllowedRoots = candidateAllowedRoots
        self.trustedRoots = trustedRoots
        self.stagingAppPath = stagingAppPath
        self.rollbackScratchAppPath = rollbackScratchAppPath
        self.identity = identity
    }

    public var hilLaunchAgentPlistPath: String {
        (launchAgentsDirectory as NSString).appendingPathComponent(
            "\(identity.hilLaunchdLabel).plist"
        )
    }

    public func plistPath(forLabel label: String) -> String {
        if label == identity.hilLaunchdLabel {
            return hilLaunchAgentPlistPath
        }
        return launchAgentPlistPath
    }

    public func managedPlistPaths() -> [String] {
        [launchAgentPlistPath, hilLaunchAgentPlistPath]
    }

    /// 冻结白名单：构造器写入的可信根，不随 backup/staging 改写而扩大。
    public var allowedRoots: [String] { trustedRoots }

    public func validateTrustedPaths() throws {
        let paths = [
            applicationsAppPath,
            backupAppPath,
            stagingAppPath,
            rollbackScratchAppPath,
            launchAgentsDirectory,
            launchAgentPlistPath,
            hilLaunchAgentPlistPath,
        ]
        for path in paths {
            do {
                _ = try AhaKeyReleasePathGuard.requireAllowed(path, roots: trustedRoots)
            } catch {
                throw AhaKeyReleasePathViolation.pathEscapesAllowedRoot(path)
            }
        }
    }

    public var preservedPaths: [String] {
        [userConfigDirectory] + hookPaths
    }

    /// 测试沙箱布局：全部落在 `root` 下。internal，不对产品公开；产品 API 只保留 `.production()`。
    static func sandboxed(root: String, identity: AhaKeyReleaseIdentity = .current) -> Self {
        let launchAgents = (root as NSString).appendingPathComponent("LaunchAgents")
        let home = (root as NSString).appendingPathComponent("Home")
        let applications = (root as NSString).appendingPathComponent("Applications")
        let userConfig = (home as NSString).appendingPathComponent("Library/Application Support/AhaKeyConfig")
        return Self(
            applicationsAppPath: (applications as NSString).appendingPathComponent(identity.appBundleFileName),
            backupAppPath: (applications as NSString).appendingPathComponent("\(identity.appBundleFileName).ahakey-backup"),
            launchAgentsDirectory: launchAgents,
            launchAgentPlistPath: (launchAgents as NSString).appendingPathComponent("\(identity.agentLaunchdLabel).plist"),
            logPath: (home as NSString).appendingPathComponent("Library/Logs/ahakeyconfig-agent.log"),
            socketPath: (home as NSString).appendingPathComponent("Library/Application Support/AhaKeyConfig/ahakey.sock"),
            userConfigDirectory: userConfig,
            hookPaths: [
                (home as NSString).appendingPathComponent(".claude/settings.json"),
                (home as NSString).appendingPathComponent(".cursor/hooks.json"),
                (home as NSString).appendingPathComponent(".codex/config.toml"),
                (home as NSString).appendingPathComponent(".kimi/config.toml"),
            ],
            permitsSystemApplicationsInstall: false,
            candidateAllowedRoots: [(root as NSString).appendingPathComponent("Candidates")],
            trustedRoots: [
                applications,
                launchAgents,
                userConfig,
                (userConfig as NSString).deletingLastPathComponent,
            ],
            stagingAppPath: (applications as NSString).appendingPathComponent("\(identity.appBundleFileName).ahakey-staging"),
            rollbackScratchAppPath: (applications as NSString).appendingPathComponent("\(identity.appBundleFileName).ahakey-rollback-scratch"),
            identity: identity
        )
    }

    /// HIL 真实安装布局。本卡不得用 `allowSystemMutation` 执行它。
    public static func production(identity: AhaKeyReleaseIdentity = .current) -> Self {
        let home = NSHomeDirectory()
        let launchAgents = (home as NSString).appendingPathComponent("Library/LaunchAgents")
        return Self(
            applicationsAppPath: "/Applications/\(identity.appBundleFileName)",
            backupAppPath: "/Applications/\(identity.appBundleFileName).ahakey-backup",
            launchAgentsDirectory: launchAgents,
            launchAgentPlistPath: (launchAgents as NSString).appendingPathComponent("\(identity.agentLaunchdLabel).plist"),
            logPath: (home as NSString).appendingPathComponent("Library/Logs/ahakeyconfig-agent.log"),
            socketPath: (home as NSString).appendingPathComponent("Library/Application Support/AhaKeyConfig/ahakey.sock"),
            userConfigDirectory: (home as NSString).appendingPathComponent("Library/Application Support/AhaKeyConfig"),
            hookPaths: [
                (home as NSString).appendingPathComponent(".claude/settings.json"),
                (home as NSString).appendingPathComponent(".cursor/hooks.json"),
                (home as NSString).appendingPathComponent(".codex/config.toml"),
                (home as NSString).appendingPathComponent(".kimi/config.toml"),
            ],
            permitsSystemApplicationsInstall: true,
            candidateAllowedRoots: [
                FileManager.default.temporaryDirectory.path,
                (home as NSString).appendingPathComponent("Downloads"),
            ],
            trustedRoots: [
                "/Applications",
                launchAgents,
                (home as NSString).appendingPathComponent("Library/Application Support/AhaKeyConfig"),
                (home as NSString).appendingPathComponent("Library/Application Support"),
            ],
            stagingAppPath: "/Applications/\(identity.appBundleFileName).ahakey-staging",
            rollbackScratchAppPath: "/Applications/\(identity.appBundleFileName).ahakey-rollback-scratch",
            identity: identity
        )
    }
}

public struct AhaKeyReleaseInstallSafety: Equatable, Sendable {
    public var allowSystemMutation: Bool

    public init(allowSystemMutation: Bool) {
        self.allowSystemMutation = allowSystemMutation
    }

    public static let sandboxOnly = AhaKeyReleaseInstallSafety(allowSystemMutation: false)
}

public enum AhaKeyReleasePreviousAppIntegrity: Equatable, Sendable {
    case missing
    case verifiedRestorable
    case nonRestorable
}

public struct AhaKeyReleaseDisabledOverrideSnapshot: Equatable, Sendable {
    public var officialDisabled: Bool
    public var hilDisabled: Bool

    public init(officialDisabled: Bool = false, hilDisabled: Bool = false) {
        self.officialDisabled = officialDisabled
        self.hilDisabled = hilDisabled
    }

    public func isDisabled(_ label: String, identity: AhaKeyReleaseIdentity = .current) -> Bool {
        if label == identity.agentLaunchdLabel { return officialDisabled }
        if label == identity.hilLaunchdLabel { return hilDisabled }
        return false
    }
}

public struct AhaKeyReleaseHostSnapshot: Equatable, Sendable {
    public var darwinMajor: Int
    public var appInstalled: Bool
    public var loadedLaunchdLabels: Set<String>
    public var loginItemRegistered: Bool
    public var preservedPathExists: [String: Bool]
    public var previousAppIntegrity: AhaKeyReleasePreviousAppIntegrity
    public var disabledOverrides: AhaKeyReleaseDisabledOverrideSnapshot
    public var installedAppFingerprint: String

    public init(
        darwinMajor: Int,
        appInstalled: Bool,
        loadedLaunchdLabels: Set<String>,
        loginItemRegistered: Bool = false,
        preservedPathExists: [String: Bool] = [:],
        previousAppIntegrity: AhaKeyReleasePreviousAppIntegrity = .missing,
        disabledOverrides: AhaKeyReleaseDisabledOverrideSnapshot = AhaKeyReleaseDisabledOverrideSnapshot(),
        installedAppFingerprint: String = ""
    ) {
        self.darwinMajor = darwinMajor
        self.appInstalled = appInstalled
        self.loadedLaunchdLabels = loadedLaunchdLabels
        self.loginItemRegistered = loginItemRegistered
        self.preservedPathExists = preservedPathExists
        self.previousAppIntegrity = appInstalled ? previousAppIntegrity : .missing
        self.disabledOverrides = disabledOverrides
        self.installedAppFingerprint = appInstalled ? installedAppFingerprint : ""
    }
}

public enum AhaKeyReleaseInstallRequest: Equatable, Sendable {
    case install(candidateAppPath: String)
    case upgrade(candidateAppPath: String)
    case uninstall
}

public enum AhaKeyReleaseInstallRejection: Equatable, Error, Sendable {
    case unsupportedMacOS(darwinMajor: Int)
    case missingCandidate
    case identityRejected(AhaKeyReleaseSigningRejection)
    case systemMutationNotAllowed
    case ambiguousPreviousOwners(Set<String>)
    case identityContextMismatch
}

public enum AhaKeyReleaseInstallStep: Equatable, Sendable {
    case bootout(label: String)
    case installApp
    case writeLaunchAgent
    case enable(label: String)
    case bootstrap(label: String)
    case restorePreviousLaunchAgent
    case removeLaunchAgent
    case registerLoginItem
    case unregisterLoginItem
    case restoreApp
    case removeApp
    case removeBackup
    case verifySingleOwner
    case verifyCleanUninstall
}

public struct AhaKeyReleaseOwnerRecord: Equatable, Sendable {
    public var label: String
    public var plistPath: String
    public var plist: Data

    public init(label: String, plistPath: String, plist: Data) {
        self.label = label
        self.plistPath = plistPath
        self.plist = plist
    }
}

public struct AhaKeyReleasePlistSnapshot: Equatable, Sendable {
    public var path: String
    public var data: Data?

    public init(path: String, data: Data?) {
        self.path = path
        self.data = data
    }
}

public struct AhaKeyReleaseInstallPlan: Equatable, Sendable {
    public let request: AhaKeyReleaseInstallRequest
    public let steps: [AhaKeyReleaseInstallStep]
    public let preservedPaths: [String]
    public let launchAgentPlist: Data
    public let candidateAppPath: String?
    public let previousOwnerLabels: Set<String>
    public let previousOwnerRecords: [AhaKeyReleaseOwnerRecord]
    public let previousManagedPlists: [AhaKeyReleasePlistSnapshot]
    public let previousLoginItemRegistered: Bool
    public let hadPreviousApp: Bool
    public let previousAppIntegrity: AhaKeyReleasePreviousAppIntegrity
    public let previousDisabledOverrides: AhaKeyReleaseDisabledOverrideSnapshot
    public let previousAppFingerprint: String
    public let candidateAppFingerprint: String
}

public struct AhaKeyReleaseMutationReceipt: Equatable, Sendable {
    public var appWasMutated: Bool
    public var completedSteps: [AhaKeyReleaseInstallStep]

    public init(appWasMutated: Bool, completedSteps: [AhaKeyReleaseInstallStep]) {
        self.appWasMutated = appWasMutated
        self.completedSteps = completedSteps
    }
}

public struct AhaKeyReleaseInstallOutcome: Equatable, Sendable {
    public let rolledBack: Bool
    public let failForwardPartial: Bool
    public let originalApplyError: AhaKeyReleaseInstallError?
    public let snapshot: AhaKeyReleaseHostSnapshot
    public let mutationReceipt: AhaKeyReleaseMutationReceipt
    public let preservedPaths: [String]

    public var completedSteps: [AhaKeyReleaseInstallStep] { mutationReceipt.completedSteps }
    public var loadedLaunchdLabels: Set<String> { snapshot.loadedLaunchdLabels }
    public var appInstalled: Bool { snapshot.appInstalled }
    public var loginItemRegistered: Bool { snapshot.loginItemRegistered }

    public init(
        rolledBack: Bool,
        failForwardPartial: Bool,
        originalApplyError: AhaKeyReleaseInstallError?,
        snapshot: AhaKeyReleaseHostSnapshot,
        mutationReceipt: AhaKeyReleaseMutationReceipt,
        preservedPaths: [String]
    ) {
        self.rolledBack = rolledBack
        self.failForwardPartial = failForwardPartial
        self.originalApplyError = originalApplyError
        self.snapshot = snapshot
        self.mutationReceipt = mutationReceipt
        self.preservedPaths = preservedPaths
    }
}

public indirect enum AhaKeyReleaseInstallError: Error, Equatable {
    case rejected(AhaKeyReleaseInstallRejection)
    case injectedFailure(AhaKeyReleaseInstallStep)
    case hostFailure(String)
    case dualOwnerRemaining(Set<String>)
    case rollbackFailed(String)
    case terminalStateMismatch(String)
    case failedAfterAppMutation(String)
    case pathViolation(AhaKeyReleasePathViolation)
    case compensationFailed(
        originalApplyError: AhaKeyReleaseInstallError,
        compensationError: AhaKeyReleaseInstallError,
        completedSteps: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool,
        snapshot: AhaKeyReleaseHostSnapshot
    )
    case blocked(
        originalApplyError: AhaKeyReleaseInstallError?,
        compensationError: AhaKeyReleaseInstallError?,
        completedSteps: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool,
        snapshot: AhaKeyReleaseHostSnapshot,
        reason: String
    )
}

public enum AhaKeyReleaseAppTreeKind: String, Equatable, Sendable {
    case file
    case directory
    case symlink
}

public struct AhaKeyReleaseAppTreeEntry: Equatable, Sendable {
    public var relativePath: String
    public var kind: AhaKeyReleaseAppTreeKind
    public var byteCount: UInt64
    public var bytes: Data
    public var symlinkTarget: String

    public init(
        relativePath: String,
        kind: AhaKeyReleaseAppTreeKind,
        byteCount: UInt64,
        bytes: Data = Data(),
        symlinkTarget: String = ""
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.byteCount = byteCount
        self.bytes = bytes
        self.symlinkTarget = symlinkTarget
    }
}

/// 全树 relative path + type + length + bytes 的 SHA-256。
/// 每个字段都是 big-endian 长度前缀，symlink target 不得与下一 path 拼接碰撞。
/// 磁盘路径流式读入；读取失败必须抛错，不得返空串继续。
public enum AhaKeyReleaseAppTreeDigest {
    public static func hex(entries: [AhaKeyReleaseAppTreeEntry]) -> String {
        var hasher = SHA256()
        for entry in entries.sorted(by: { $0.relativePath < $1.relativePath }) {
            append(entry: entry, to: &hasher)
        }
        return hex(hasher)
    }

    public static func hex(at directory: String, fileManager: FileManager = .default) throws -> String {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            throw AhaKeyReleaseInstallError.hostFailure("app tree unreadable at \(directory)")
        }
        var hasher = SHA256()
        try stream(at: directory, relative: "", fileManager: fileManager, hasher: &hasher)
        return hex(hasher)
    }

    public static func entries(fromNamedFiles names: Set<String>) -> [AhaKeyReleaseAppTreeEntry] {
        names.sorted().map { name in
            let data = Data(name.utf8)
            return AhaKeyReleaseAppTreeEntry(
                relativePath: name,
                kind: .file,
                byteCount: UInt64(data.count),
                bytes: data
            )
        }
    }

    private static func hex(_ hasher: SHA256) -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func append(entry: AhaKeyReleaseAppTreeEntry, to hasher: inout SHA256) {
        append(string: entry.relativePath, to: &hasher)
        append(string: entry.kind.rawValue, to: &hasher)
        append(uInt64: entry.byteCount, to: &hasher)
        switch entry.kind {
        case .file:
            hasher.update(data: entry.bytes)
        case .symlink:
            append(string: entry.symlinkTarget, to: &hasher)
        case .directory:
            break
        }
    }

    private static func stream(
        at path: String,
        relative: String,
        fileManager: FileManager,
        hasher: inout SHA256
    ) throws {
        if relative.isEmpty {
            let names = try directoryNames(at: path, fileManager: fileManager)
            for name in names {
                try stream(
                    at: (path as NSString).appendingPathComponent(name),
                    relative: name,
                    fileManager: fileManager,
                    hasher: &hasher
                )
            }
            return
        }
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: path) {
            append(
                entry: AhaKeyReleaseAppTreeEntry(
                    relativePath: relative,
                    kind: .symlink,
                    byteCount: 0,
                    symlinkTarget: target
                ),
                to: &hasher
            )
            return
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            throw AhaKeyReleaseInstallError.hostFailure("app tree unreadable at \(path)")
        }
        if isDir.boolValue {
            append(
                entry: AhaKeyReleaseAppTreeEntry(
                    relativePath: relative,
                    kind: .directory,
                    byteCount: 0
                ),
                to: &hasher
            )
            let names = try directoryNames(at: path, fileManager: fileManager)
            for name in names {
                try stream(
                    at: (path as NSString).appendingPathComponent(name),
                    relative: relative + "/" + name,
                    fileManager: fileManager,
                    hasher: &hasher
                )
            }
            return
        }
        let size: UInt64
        do {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            throw AhaKeyReleaseInstallError.hostFailure("app tree unreadable at \(path): \(error)")
        }
        append(string: relative, to: &hasher)
        append(string: AhaKeyReleaseAppTreeKind.file.rawValue, to: &hasher)
        append(uInt64: size, to: &hasher)
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            while true {
                let chunk = handle.readData(ofLength: 65_536)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
        } catch {
            throw AhaKeyReleaseInstallError.hostFailure("app tree unreadable at \(path): \(error)")
        }
    }

    private static func directoryNames(at path: String, fileManager: FileManager) throws -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: path).sorted()
        } catch {
            throw AhaKeyReleaseInstallError.hostFailure("app tree unreadable at \(path): \(error)")
        }
    }

    private static func append(string: String, to hasher: inout SHA256) {
        let data = Data(string.utf8)
        append(uInt64: UInt64(data.count), to: &hasher)
        hasher.update(data: data)
    }

    private static func append(uInt64 value: UInt64, to hasher: inout SHA256) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { raw in
            hasher.update(data: Data(raw))
        }
    }
}

/// 安装器与测试共用的 host 缝：真实实现走文件原子替换 + 可注入 launchd；测试可完全内存化。
public protocol AhaKeyReleaseInstallHost: AnyObject {
    var identity: AhaKeyReleaseIdentity { get }
    func snapshot(layout: AhaKeyReleaseInstallLayout) throws -> AhaKeyReleaseHostSnapshot
    func inspectCandidate(at appPath: String, identity: AhaKeyReleaseIdentity) throws -> AhaKeyReleaseCandidateReport
    func appFingerprint(at path: String) throws -> String
    func itemExists(at path: String) -> Bool
    func isSymlink(_ path: String) -> Bool
    func resolvedPath(_ path: String) -> String?
    func replaceDirectoryAtomically(from: String, to: String, backup: String, staging: String) throws
    func moveDirectoryAtomically(from: String, to: String) throws
    func removeTree(_ path: String) throws
    func writeFile(at path: String, data: Data) throws
    func readFile(at path: String) -> Data?
    func bootout(label: String) throws
    func bootstrap(label: String, plistPath: String) throws
    func registerLoginItem() throws
    func unregisterLoginItem() throws
    func disabledLaunchdLabels() throws -> Set<String>
    func setLaunchdDisabled(label: String, disabled: Bool) throws
}

public enum AhaKeyReleaseInstallPlanner {
    public static func competingLabels(
        in loaded: Set<String>,
        identity: AhaKeyReleaseIdentity = .current
    ) -> Set<String> {
        loaded.filter { identity.isAhaKeyLaunchdLabel($0) }
    }

    public static func plan(
        request: AhaKeyReleaseInstallRequest,
        snapshot: AhaKeyReleaseHostSnapshot,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity = .current,
        candidate: AhaKeyReleaseCandidateReport? = nil,
        previousOwnerRecords: [AhaKeyReleaseOwnerRecord] = [],
        previousManagedPlists: [AhaKeyReleasePlistSnapshot] = [],
        safety: AhaKeyReleaseInstallSafety = .sandboxOnly,
        candidateAppFingerprint: String = ""
    ) -> Result<AhaKeyReleaseInstallPlan, AhaKeyReleaseInstallRejection> {
        if layout.identity != identity {
            return .failure(.identityContextMismatch)
        }
        if snapshot.darwinMajor < identity.minimumDarwinMajor {
            return .failure(.unsupportedMacOS(darwinMajor: snapshot.darwinMajor))
        }
        if layout.permitsSystemApplicationsInstall && !safety.allowSystemMutation {
            return .failure(.systemMutationNotAllowed)
        }

        let preserved = layout.preservedPaths
        let previousOwners = competingLabels(in: snapshot.loadedLaunchdLabels, identity: identity)
        let knownOwners: Set<String> = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        if !previousOwners.isSubset(of: knownOwners) {
            return .failure(.ambiguousPreviousOwners(previousOwners))
        }
        let recordLabels = Set(previousOwnerRecords.map(\.label))
        if recordLabels != previousOwners {
            return .failure(.ambiguousPreviousOwners(previousOwners))
        }

        switch request {
        case .uninstall:
            var steps: [AhaKeyReleaseInstallStep] = previousOwners.sorted().map { .bootout(label: $0) }
            steps.append(.unregisterLoginItem)
            steps.append(.removeLaunchAgent)
            if snapshot.appInstalled {
                steps.append(.removeApp)
            }
            steps.append(.verifyCleanUninstall)
            if snapshot.appInstalled {
                steps.append(.removeBackup)
            }
            return .success(AhaKeyReleaseInstallPlan(
                request: request,
                steps: steps,
                preservedPaths: preserved,
                launchAgentPlist: Data(),
                candidateAppPath: nil,
                previousOwnerLabels: previousOwners,
                previousOwnerRecords: previousOwnerRecords,
                previousManagedPlists: previousManagedPlists,
                previousLoginItemRegistered: snapshot.loginItemRegistered,
                hadPreviousApp: snapshot.appInstalled,
                previousAppIntegrity: snapshot.previousAppIntegrity,
                previousDisabledOverrides: snapshot.disabledOverrides,
                previousAppFingerprint: snapshot.installedAppFingerprint,
                candidateAppFingerprint: ""
            ))

        case .install(let candidatePath), .upgrade(let candidatePath):
            if candidatePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(.missingCandidate)
            }
            switch AhaKeyReleaseSigningChecklist.check(candidate, identity: identity) {
            case .rejected(let reason):
                return .failure(.identityRejected(reason))
            case .unsignedCandidateReady, .signedIdentityMatches:
                break
            }
            let agentPath = identity.agentBinaryPath(inApp: layout.applicationsAppPath)
            guard let plist = try? identity.launchAgentPlist(
                agentBinaryPath: agentPath,
                socketPath: layout.socketPath,
                logPath: layout.logPath
            ) else {
                return .failure(.identityRejected(.machServiceMissing))
            }

            var steps: [AhaKeyReleaseInstallStep] = previousOwners.sorted().map { .bootout(label: $0) }
            steps.append(.installApp)
            steps.append(.writeLaunchAgent)
            steps.append(.enable(label: identity.agentLaunchdLabel))
            steps.append(.bootstrap(label: identity.agentLaunchdLabel))
            steps.append(.registerLoginItem)
            steps.append(.verifySingleOwner)
            if snapshot.appInstalled, snapshot.previousAppIntegrity != .nonRestorable {
                steps.append(.removeBackup)
            }
            return .success(AhaKeyReleaseInstallPlan(
                request: request,
                steps: steps,
                preservedPaths: preserved,
                launchAgentPlist: plist,
                candidateAppPath: candidatePath,
                previousOwnerLabels: previousOwners,
                previousOwnerRecords: previousOwnerRecords,
                previousManagedPlists: previousManagedPlists,
                previousLoginItemRegistered: snapshot.loginItemRegistered,
                hadPreviousApp: snapshot.appInstalled,
                previousAppIntegrity: snapshot.previousAppIntegrity,
                previousDisabledOverrides: snapshot.disabledOverrides,
                previousAppFingerprint: snapshot.installedAppFingerprint,
                candidateAppFingerprint: candidateAppFingerprint
            ))
        }
    }
}

/// HIL 与测试共用入口：始终自行 inspect 候选，不信任调用方预检。
public enum AhaKeyReleaseInstaller {
    public static func run(
        request: AhaKeyReleaseInstallRequest,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity = .current,
        safety: AhaKeyReleaseInstallSafety = .sandboxOnly,
        injectFailureAt: AhaKeyReleaseInstallStep? = nil
    ) throws -> AhaKeyReleaseInstallOutcome {
        try requireUnifiedIdentity(host: host, layout: layout, identity: identity)
        do {
            try layout.validateTrustedPaths()
        } catch let violation as AhaKeyReleasePathViolation {
            throw AhaKeyReleaseInstallError.pathViolation(violation)
        }
        let snapshot = try host.snapshot(layout: layout)
        var inspected: AhaKeyReleaseCandidateReport?
        let owners = AhaKeyReleaseInstallPlanner.competingLabels(
            in: snapshot.loadedLaunchdLabels,
            identity: identity
        )
        var records: [AhaKeyReleaseOwnerRecord] = []
        for label in owners.sorted() {
            let path = layout.plistPath(forLabel: label)
            guard let data = host.readFile(at: path) else {
                throw AhaKeyReleaseInstallError.rejected(.ambiguousPreviousOwners(owners))
            }
            records.append(AhaKeyReleaseOwnerRecord(label: label, plistPath: path, plist: data))
        }
        let managedPlists = layout.managedPlistPaths().map { path in
            AhaKeyReleasePlistSnapshot(path: path, data: host.readFile(at: path))
        }
        var candidateAppFingerprint = ""
        switch request {
        case .install(let path), .upgrade(let path):
            do {
                inspected = try host.inspectCandidate(at: path, identity: identity)
            } catch {
                throw AhaKeyReleaseInstallError.rejected(.identityRejected(.candidateNotInspected))
            }
            candidateAppFingerprint = try host.appFingerprint(at: path)
        case .uninstall:
            break
        }
        let planned = AhaKeyReleaseInstallPlanner.plan(
            request: request,
            snapshot: snapshot,
            layout: layout,
            identity: identity,
            candidate: inspected,
            previousOwnerRecords: records,
            previousManagedPlists: managedPlists,
            safety: safety,
            candidateAppFingerprint: candidateAppFingerprint
        )
        switch planned {
        case .failure(let rejection):
            throw AhaKeyReleaseInstallError.rejected(rejection)
        case .success(let plan):
            return try AhaKeyReleaseInstallEngine.apply(
                plan: plan,
                host: host,
                layout: layout,
                identity: identity,
                safety: safety,
                injectFailureAt: injectFailureAt
            )
        }
    }
}

private func requireUnifiedIdentity(
    host: AhaKeyReleaseInstallHost,
    layout: AhaKeyReleaseInstallLayout,
    identity: AhaKeyReleaseIdentity
) throws {
    if host.identity != identity || layout.identity != identity {
        throw AhaKeyReleaseInstallError.rejected(.identityContextMismatch)
    }
}

private func makeInstallOutcome(
    rolledBack: Bool,
    failForwardPartial: Bool,
    originalApplyError: AhaKeyReleaseInstallError?,
    snapshot: AhaKeyReleaseHostSnapshot,
    appWasMutated: Bool,
    completedSteps: [AhaKeyReleaseInstallStep],
    preservedPaths: [String]
) -> AhaKeyReleaseInstallOutcome {
    AhaKeyReleaseInstallOutcome(
        rolledBack: rolledBack,
        failForwardPartial: failForwardPartial,
        originalApplyError: originalApplyError,
        snapshot: snapshot,
        mutationReceipt: AhaKeyReleaseMutationReceipt(
            appWasMutated: appWasMutated,
            completedSteps: completedSteps
        ),
        preservedPaths: preservedPaths
    )
}

public enum AhaKeyReleaseInstallEngine {
    public static func apply(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity = .current,
        safety: AhaKeyReleaseInstallSafety = .sandboxOnly,
        injectFailureAt: AhaKeyReleaseInstallStep? = nil
    ) throws -> AhaKeyReleaseInstallOutcome {
        try requireUnifiedIdentity(host: host, layout: layout, identity: identity)
        do {
            try layout.validateTrustedPaths()
        } catch let violation as AhaKeyReleasePathViolation {
            throw AhaKeyReleaseInstallError.pathViolation(violation)
        }
        if layout.permitsSystemApplicationsInstall && !safety.allowSystemMutation {
            throw AhaKeyReleaseInstallError.rejected(.systemMutationNotAllowed)
        }
        if case .install(let path) = plan.request {
            try inspectAtApply(path, host: host, identity: identity)
        }
        if case .upgrade(let path) = plan.request {
            try inspectAtApply(path, host: host, identity: identity)
        }

        var completed: [AhaKeyReleaseInstallStep] = []
        do {
            for step in plan.steps {
                try perform(step, plan: plan, host: host, layout: layout, identity: identity)
                completed.append(step)
                if step == injectFailureAt {
                    throw AhaKeyReleaseInstallError.injectedFailure(step)
                }
            }
            let snap = try host.snapshot(layout: layout)
            try verifyTerminalState(
                plan: plan,
                snapshot: snap,
                host: host,
                layout: layout,
                identity: identity,
                rolledBack: false,
                originalApplyError: nil,
                completed: completed,
                appWasMutated: completed.contains(.installApp) || completed.contains(.removeApp)
            )
            return makeInstallOutcome(
                rolledBack: false,
                failForwardPartial: false,
                originalApplyError: nil,
                snapshot: snap,
                appWasMutated: completed.contains(.installApp) || completed.contains(.removeApp),
                completedSteps: completed,
                preservedPaths: plan.preservedPaths
            )
        } catch {
            let originalError = asInstallError(error)
            let appWasMutated = appMutationOccurred(completed: completed, error: error)
            let compensationKind: CompensationKind
            do {
                compensationKind = try rollback(
                    completed: completed,
                    plan: plan,
                    host: host,
                    layout: layout,
                    identity: identity,
                    appWasMutated: appWasMutated,
                    originalApplyError: originalError
                )
            } catch let compensationError {
                throw wrapCompensationFailure(
                    original: originalError,
                    compensation: compensationError,
                    completed: completed,
                    appWasMutated: appWasMutated,
                    host: host,
                    layout: layout
                )
            }
            let snap = try host.snapshot(layout: layout)
            do {
                try verifyTerminalState(
                    plan: plan,
                    snapshot: snap,
                    host: host,
                    layout: layout,
                    identity: identity,
                    rolledBack: compensationKind == .exactRollback,
                    failForwardPartial: compensationKind == .failForwardPartial,
                    originalApplyError: originalError,
                    completed: completed,
                    appWasMutated: appWasMutated
                )
            } catch let verifyError {
                throw wrapCompensationFailure(
                    original: originalError,
                    compensation: verifyError,
                    completed: completed,
                    appWasMutated: appWasMutated,
                    host: host,
                    layout: layout
                )
            }
            if compensationKind == .failForwardPartial {
                return makeInstallOutcome(
                    rolledBack: false,
                    failForwardPartial: true,
                    originalApplyError: originalError,
                    snapshot: snap,
                    appWasMutated: appWasMutated,
                    completedSteps: completed,
                    preservedPaths: plan.preservedPaths
                )
            }
            if injectFailureAt != nil || isRecoverableMutationFailure(originalError) {
                return makeInstallOutcome(
                    rolledBack: true,
                    failForwardPartial: false,
                    originalApplyError: originalError,
                    snapshot: snap,
                    appWasMutated: appWasMutated,
                    completedSteps: completed,
                    preservedPaths: plan.preservedPaths
                )
            }
            throw originalError
        }
    }

    private static func inspectAtApply(
        _ path: String,
        host: AhaKeyReleaseInstallHost,
        identity: AhaKeyReleaseIdentity
    ) throws {
        let report: AhaKeyReleaseCandidateReport
        do {
            report = try host.inspectCandidate(at: path, identity: identity)
        } catch {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.candidateNotInspected))
        }
        if case .rejected(let reason) = AhaKeyReleaseSigningChecklist.check(report, identity: identity) {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(reason))
        }
    }

    private static func verifyTerminalState(
        plan: AhaKeyReleaseInstallPlan,
        snapshot: AhaKeyReleaseHostSnapshot,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity,
        rolledBack: Bool,
        failForwardPartial: Bool = false,
        originalApplyError: AhaKeyReleaseInstallError?,
        completed: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool
    ) throws {
        do {
            try verifyTerminalStateUnwrapped(
                plan: plan,
                snapshot: snapshot,
                host: host,
                layout: layout,
                identity: identity,
                rolledBack: rolledBack,
                failForwardPartial: failForwardPartial,
                originalApplyError: originalApplyError,
                completed: completed,
                appWasMutated: appWasMutated
            )
        } catch {
            throw completeCompensationMismatch(
                original: originalApplyError,
                compensation: error,
                completed: completed,
                appWasMutated: appWasMutated,
                snapshot: snapshot
            )
        }
    }

    private static func verifyTerminalStateUnwrapped(
        plan: AhaKeyReleaseInstallPlan,
        snapshot: AhaKeyReleaseHostSnapshot,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity,
        rolledBack: Bool,
        failForwardPartial: Bool,
        originalApplyError: AhaKeyReleaseInstallError?,
        completed: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool
    ) throws {
        let owners = AhaKeyReleaseInstallPlanner.competingLabels(
            in: snapshot.loadedLaunchdLabels,
            identity: identity
        )
        if failForwardPartial {
            if !snapshot.appInstalled {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("candidate app missing after fail-forward")
            }
            if snapshot.loginItemRegistered != plan.previousLoginItemRegistered {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("loginItem mismatch")
            }
            try verifyAppTerminal(
                plan: plan,
                snapshot: snapshot,
                failForwardPartial: true,
                rolledBack: false
            )
            try verifyCompensationOwnersAndDisabled(
                plan: plan,
                snapshot: snapshot,
                owners: owners,
                requireUniqueOwner: true,
                originalApplyError: originalApplyError,
                completed: completed,
                appWasMutated: appWasMutated
            )
            try verifyManagedPlists(plan.previousManagedPlists, host: host, asRollback: true)
            return
        }
        if rolledBack {
            if snapshot.appInstalled != plan.hadPreviousApp {
                throw AhaKeyReleaseInstallError.rollbackFailed("appInstalled=\(snapshot.appInstalled) expected \(plan.hadPreviousApp)")
            }
            if snapshot.loginItemRegistered != plan.previousLoginItemRegistered {
                throw AhaKeyReleaseInstallError.rollbackFailed("loginItem mismatch")
            }
            try verifyAppTerminal(
                plan: plan,
                snapshot: snapshot,
                failForwardPartial: false,
                rolledBack: true
            )
            try verifyCompensationOwnersAndDisabled(
                plan: plan,
                snapshot: snapshot,
                owners: owners,
                requireUniqueOwner: false,
                originalApplyError: originalApplyError,
                completed: completed,
                appWasMutated: appWasMutated
            )
            try verifyManagedPlists(plan.previousManagedPlists, host: host, asRollback: true)
            return
        }
        switch plan.request {
        case .uninstall:
            if !owners.isEmpty {
                throw AhaKeyReleaseInstallError.dualOwnerRemaining(owners)
            }
            if snapshot.appInstalled {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("app still installed after uninstall")
            }
            if snapshot.loginItemRegistered {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("login item still registered after uninstall")
            }
            if snapshot.previousAppIntegrity != .missing || !snapshot.installedAppFingerprint.isEmpty {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("uninstall left a restorable or unidentified app tree")
            }
            for path in layout.managedPlistPaths() {
                if host.readFile(at: path) != nil {
                    throw AhaKeyReleaseInstallError.terminalStateMismatch("managed plist remains at \(path)")
                }
            }
        case .install, .upgrade:
            if owners != [identity.agentLaunchdLabel] {
                throw AhaKeyReleaseInstallError.dualOwnerRemaining(owners)
            }
            if !snapshot.appInstalled {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("app missing after install")
            }
            if !snapshot.loginItemRegistered {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("login item missing after install")
            }
            if host.readFile(at: layout.launchAgentPlistPath) != plan.launchAgentPlist {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("official plist mismatch after install")
            }
            try verifyAppTerminal(
                plan: plan,
                snapshot: snapshot,
                failForwardPartial: false,
                rolledBack: false
            )
        }
    }

    private static func verifyAppTerminal(
        plan: AhaKeyReleaseInstallPlan,
        snapshot: AhaKeyReleaseHostSnapshot,
        failForwardPartial: Bool,
        rolledBack: Bool
    ) throws {
        if failForwardPartial {
            if snapshot.previousAppIntegrity != .verifiedRestorable {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("fail-forward app is not a verified candidate")
            }
            if snapshot.installedAppFingerprint != plan.candidateAppFingerprint {
                throw AhaKeyReleaseInstallError.terminalStateMismatch("fail-forward app tree mismatch")
            }
            return
        }
        if rolledBack {
            if !plan.hadPreviousApp {
                if snapshot.appInstalled
                    || snapshot.previousAppIntegrity != .missing
                    || !snapshot.installedAppFingerprint.isEmpty {
                    throw AhaKeyReleaseInstallError.rollbackFailed("clean install rollback left an app")
                }
                return
            }
            if plan.previousAppIntegrity == .verifiedRestorable {
                if snapshot.previousAppIntegrity != .verifiedRestorable {
                    throw AhaKeyReleaseInstallError.rollbackFailed("restored app integrity failed")
                }
                if snapshot.installedAppFingerprint != plan.previousAppFingerprint {
                    throw AhaKeyReleaseInstallError.rollbackFailed("restored app tree mismatch")
                }
            }
            return
        }
        if snapshot.previousAppIntegrity != .verifiedRestorable {
            throw AhaKeyReleaseInstallError.terminalStateMismatch("installed app integrity failed")
        }
        if snapshot.installedAppFingerprint != plan.candidateAppFingerprint {
            throw AhaKeyReleaseInstallError.terminalStateMismatch("installed app tree mismatch")
        }
    }

    private static func completeCompensationMismatch(
        original: AhaKeyReleaseInstallError?,
        compensation: Error,
        completed: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool,
        snapshot: AhaKeyReleaseHostSnapshot
    ) -> AhaKeyReleaseInstallError {
        let compensationError = asInstallError(compensation)
        if case .blocked = compensationError {
            return compensationError
        }
        guard let original else {
            return compensationError
        }
        return .blocked(
            originalApplyError: original,
            compensationError: compensationError,
            completedSteps: completed,
            appWasMutated: appWasMutated,
            snapshot: snapshot,
            reason: compensationReason(compensationError)
        )
    }

    private static func compensationReason(_ error: AhaKeyReleaseInstallError) -> String {
        switch error {
        case .dualOwnerRemaining:
            return "compensation owner mismatch"
        case .terminalStateMismatch(let message), .rollbackFailed(let message):
            if message.lowercased().contains("disabled") {
                return "compensation disabled override mismatch"
            }
            if message.lowercased().contains("unique owner") {
                return "nonRestorable compensation cannot restore a unique owner"
            }
            if message.lowercased().contains("integrity") || message.lowercased().contains("tree") {
                return "compensation app integrity mismatch"
            }
            return message
        default:
            return String(describing: error)
        }
    }

    private static func verifyManagedPlists(
        _ snapshots: [AhaKeyReleasePlistSnapshot],
        host: AhaKeyReleaseInstallHost,
        asRollback: Bool
    ) throws {
        for snapshot in snapshots {
            if host.readFile(at: snapshot.path) != snapshot.data {
                let message = "managed plist mismatch for \(snapshot.path)"
                if asRollback {
                    throw AhaKeyReleaseInstallError.rollbackFailed(message)
                }
                throw AhaKeyReleaseInstallError.terminalStateMismatch(message)
            }
        }
    }

    private static func perform(
        _ step: AhaKeyReleaseInstallStep,
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity
    ) throws {
        switch step {
        case .bootout(let label):
            try host.bootout(label: label)
        case .installApp:
            try installCandidate(plan: plan, host: host, layout: layout, identity: identity)
        case .writeLaunchAgent:
            try guardedWrite(layout.launchAgentPlistPath, data: plan.launchAgentPlist, host: host, layout: layout)
        case .enable(let label):
            try host.setLaunchdDisabled(label: label, disabled: false)
        case .bootstrap(let label):
            try host.bootstrap(label: label, plistPath: layout.launchAgentPlistPath)
        case .restorePreviousLaunchAgent:
            try restoreManagedPlists(plan: plan, host: host, layout: layout)
        case .removeLaunchAgent:
            for path in layout.managedPlistPaths() {
                if host.itemExists(at: path) {
                    try guardedRemove(path, host: host, layout: layout)
                }
            }
        case .registerLoginItem:
            try host.registerLoginItem()
        case .unregisterLoginItem:
            try host.unregisterLoginItem()
        case .restoreApp:
            try restoreApp(host: host, layout: layout, appWasMutated: true)
        case .removeApp:
            try setAsideInstalledApp(plan: plan, host: host, layout: layout)
        case .removeBackup:
            if host.itemExists(at: layout.backupAppPath) {
                try guardedRemove(layout.backupAppPath, host: host, layout: layout)
            }
        case .verifySingleOwner, .verifyCleanUninstall:
            let snap = try host.snapshot(layout: layout)
            try verifyTerminalState(
                plan: plan,
                snapshot: snap,
                host: host,
                layout: layout,
                identity: identity,
                rolledBack: false,
                originalApplyError: nil,
                completed: [],
                appWasMutated: false
            )
        }
    }

    private static func installCandidate(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity
    ) throws {
        _ = identity
        guard let candidate = plan.candidateAppPath, !candidate.isEmpty else {
            throw AhaKeyReleaseInstallError.rejected(.missingCandidate)
        }
        try validateReplacement(
            source: candidate,
            destination: layout.applicationsAppPath,
            backup: layout.backupAppPath,
            staging: layout.stagingAppPath,
            host: host,
            layout: layout,
            sourceIsCandidate: true
        )
        try host.replaceDirectoryAtomically(
            from: candidate,
            to: layout.applicationsAppPath,
            backup: layout.backupAppPath,
            staging: layout.stagingAppPath
        )
    }

    private static func setAsideInstalledApp(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout
    ) throws {
        guard plan.hadPreviousApp, host.itemExists(at: layout.applicationsAppPath) else { return }
        do {
            try AhaKeyReleasePathGuard.validateMove(
                from: layout.applicationsAppPath,
                to: layout.backupAppPath,
                allowedRoots: layout.allowedRoots,
                permitsApplicationsDestination: layout.permitsSystemApplicationsInstall,
                itemExists: host.itemExists(at:),
                resolve: host.resolvedPath,
                isSymlink: host.isSymlink
            )
        } catch let violation as AhaKeyReleasePathViolation {
            throw AhaKeyReleaseInstallError.pathViolation(violation)
        }
        try host.moveDirectoryAtomically(from: layout.applicationsAppPath, to: layout.backupAppPath)
    }

    private static func validateReplacement(
        source: String,
        destination: String,
        backup: String,
        staging: String,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        sourceIsCandidate: Bool
    ) throws {
        do {
            try AhaKeyReleasePathGuard.validateReplacement(
                source: source,
                destination: destination,
                backup: backup,
                staging: staging,
                allowedRoots: layout.allowedRoots,
                candidateRoots: layout.candidateAllowedRoots,
                sourceIsCandidate: sourceIsCandidate,
                permitsApplicationsDestination: layout.permitsSystemApplicationsInstall,
                itemExists: host.itemExists(at:),
                resolve: host.resolvedPath,
                isSymlink: host.isSymlink
            )
        } catch let violation as AhaKeyReleasePathViolation {
            throw AhaKeyReleaseInstallError.pathViolation(violation)
        }
    }

    private static func restoreApp(
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        appWasMutated: Bool
    ) throws {
        if !appWasMutated {
            return
        }
        let scratch = layout.rollbackScratchAppPath
        guard host.itemExists(at: layout.backupAppPath) else {
            if host.itemExists(at: layout.applicationsAppPath) {
                try guardedRemove(layout.applicationsAppPath, host: host, layout: layout)
            }
            return
        }
        try validateReplacement(
            source: layout.backupAppPath,
            destination: layout.applicationsAppPath,
            backup: scratch,
            staging: layout.stagingAppPath,
            host: host,
            layout: layout,
            sourceIsCandidate: false
        )
        try host.replaceDirectoryAtomically(
            from: layout.backupAppPath,
            to: layout.applicationsAppPath,
            backup: scratch,
            staging: layout.stagingAppPath
        )
        if host.itemExists(at: scratch) {
            try guardedRemove(scratch, host: host, layout: layout)
        }
        if host.itemExists(at: layout.backupAppPath) {
            try guardedRemove(layout.backupAppPath, host: host, layout: layout)
        }
    }

    private static func guardedRemove(
        _ path: String,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout
    ) throws {
        do {
            try AhaKeyReleasePathGuard.validateDestructive(
                path,
                allowedRoots: layout.allowedRoots,
                permitsApplicationsDestination: layout.permitsSystemApplicationsInstall,
                resolve: host.resolvedPath,
                isSymlink: host.isSymlink
            )
        } catch let violation as AhaKeyReleasePathViolation {
            throw AhaKeyReleaseInstallError.pathViolation(violation)
        }
        try host.removeTree(path)
    }

    private static func guardedWrite(
        _ path: String,
        data: Data,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout
    ) throws {
        do {
            try AhaKeyReleasePathGuard.validateDestructive(
                path,
                allowedRoots: layout.allowedRoots,
                permitsApplicationsDestination: layout.permitsSystemApplicationsInstall,
                resolve: host.resolvedPath,
                isSymlink: host.isSymlink
            )
        } catch let violation as AhaKeyReleasePathViolation {
            throw AhaKeyReleaseInstallError.pathViolation(violation)
        }
        try host.writeFile(at: path, data: data)
    }

    private static func restoreManagedPlists(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout
    ) throws {
        for snapshot in plan.previousManagedPlists {
            if let data = snapshot.data {
                try guardedWrite(snapshot.path, data: data, host: host, layout: layout)
            } else if host.itemExists(at: snapshot.path) {
                try guardedRemove(snapshot.path, host: host, layout: layout)
            }
        }
    }

    private static func appMutationOccurred(completed: [AhaKeyReleaseInstallStep], error: Error) -> Bool {
        if completed.contains(.installApp) || completed.contains(.removeApp) {
            return true
        }
        return isRecoverableMutationFailure(error)
    }

    private static func isRecoverableMutationFailure(_ error: Error) -> Bool {
        if case .failedAfterAppMutation = error as? AhaKeyReleaseInstallError {
            return true
        }
        return false
    }

    private static func asInstallError(_ error: Error) -> AhaKeyReleaseInstallError {
        error as? AhaKeyReleaseInstallError ?? .hostFailure(String(describing: error))
    }

    private static func wrapCompensationFailure(
        original: AhaKeyReleaseInstallError,
        compensation: Error,
        completed: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout
    ) -> AhaKeyReleaseInstallError {
        let installed = host.itemExists(at: layout.applicationsAppPath)
        let snap: AhaKeyReleaseHostSnapshot
        do {
            snap = try host.snapshot(layout: layout)
        } catch {
            return .compensationFailed(
                originalApplyError: original,
                compensationError: asInstallError(error),
                completedSteps: completed,
                appWasMutated: appWasMutated,
                snapshot: AhaKeyReleaseHostSnapshot(
                    darwinMajor: 0,
                    appInstalled: installed,
                    loadedLaunchdLabels: [],
                    installedAppFingerprint: ""
                )
            )
        }
        let compensationError = asInstallError(compensation)
        if case .blocked(let orig, let nested, _, _, let blockedSnap, let reason) = compensationError {
            return .blocked(
                originalApplyError: orig ?? original,
                compensationError: nested,
                completedSteps: completed,
                appWasMutated: appWasMutated,
                snapshot: blockedSnap,
                reason: reason
            )
        }
        if case .compensationFailed = compensationError {
            return compensationError
        }
        return .compensationFailed(
            originalApplyError: original,
            compensationError: compensationError,
            completedSteps: completed,
            appWasMutated: appWasMutated,
            snapshot: snap
        )
    }

    private enum CompensationKind {
        case exactRollback
        case failForwardPartial
    }

    private static func rollback(
        completed: [AhaKeyReleaseInstallStep],
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity,
        appWasMutated: Bool,
        originalApplyError: AhaKeyReleaseInstallError
    ) throws -> CompensationKind {
        if try host.snapshot(layout: layout).loginItemRegistered != plan.previousLoginItemRegistered {
            if plan.previousLoginItemRegistered {
                try host.registerLoginItem()
            } else {
                try host.unregisterLoginItem()
            }
        }

        if plan.previousAppIntegrity != .nonRestorable {
            try restoreApp(host: host, layout: layout, appWasMutated: appWasMutated)
        }

        let currentOwners = AhaKeyReleaseInstallPlanner.competingLabels(
            in: try host.snapshot(layout: layout).loadedLaunchdLabels,
            identity: identity
        )
        for extra in currentOwners.subtracting(plan.previousOwnerLabels) {
            try host.bootout(label: extra)
        }

        try restoreManagedPlists(plan: plan, host: host, layout: layout)
        var ownersAfterRestore = AhaKeyReleaseInstallPlanner.competingLabels(
            in: try host.snapshot(layout: layout).loadedLaunchdLabels,
            identity: identity
        )
        for record in plan.previousOwnerRecords {
            if !ownersAfterRestore.contains(record.label) {
                try host.setLaunchdDisabled(label: record.label, disabled: false)
                try host.bootstrap(label: record.label, plistPath: record.plistPath)
                ownersAfterRestore.insert(record.label)
            }
        }

        for leftover in AhaKeyReleaseInstallPlanner.competingLabels(
            in: try host.snapshot(layout: layout).loadedLaunchdLabels,
            identity: identity
        ).subtracting(plan.previousOwnerLabels) {
            try host.bootout(label: leftover)
        }
        try restoreDisabledOverrides(plan: plan, host: host, identity: identity)

        if !plan.hadPreviousApp, appWasMutated {
            if host.itemExists(at: layout.applicationsAppPath) {
                try guardedRemove(layout.applicationsAppPath, host: host, layout: layout)
            }
            if host.itemExists(at: layout.backupAppPath) {
                try guardedRemove(layout.backupAppPath, host: host, layout: layout)
            }
            if host.itemExists(at: layout.stagingAppPath) {
                try guardedRemove(layout.stagingAppPath, host: host, layout: layout)
            }
            if host.itemExists(at: layout.rollbackScratchAppPath) {
                try guardedRemove(layout.rollbackScratchAppPath, host: host, layout: layout)
            }
        }

        if plan.previousAppIntegrity == .nonRestorable, plan.hadPreviousApp {
            let snap = try host.snapshot(layout: layout)
            let owners = AhaKeyReleaseInstallPlanner.competingLabels(
                in: snap.loadedLaunchdLabels,
                identity: identity
            )
            try verifyCompensationOwnersAndDisabled(
                plan: plan,
                snapshot: snap,
                owners: owners,
                requireUniqueOwner: true,
                originalApplyError: originalApplyError,
                completed: completed,
                appWasMutated: appWasMutated
            )
            return .failForwardPartial
        }
        return .exactRollback
    }

    private static func verifyCompensationOwnersAndDisabled(
        plan: AhaKeyReleaseInstallPlan,
        snapshot: AhaKeyReleaseHostSnapshot,
        owners: Set<String>,
        requireUniqueOwner: Bool,
        originalApplyError: AhaKeyReleaseInstallError?,
        completed: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool
    ) throws {
        if requireUniqueOwner, owners.count != 1 {
            throw compensationMismatch(
                original: originalApplyError,
                compensation: .dualOwnerRemaining(owners),
                completed: completed,
                appWasMutated: appWasMutated,
                snapshot: snapshot,
                reason: "nonRestorable compensation cannot restore a unique owner"
            )
        }
        if owners != plan.previousOwnerLabels {
            throw compensationMismatch(
                original: originalApplyError,
                compensation: .dualOwnerRemaining(owners),
                completed: completed,
                appWasMutated: appWasMutated,
                snapshot: snapshot,
                reason: "compensation owner mismatch"
            )
        }
        if snapshot.disabledOverrides != plan.previousDisabledOverrides {
            throw compensationMismatch(
                original: originalApplyError,
                compensation: .terminalStateMismatch("disabled override mismatch"),
                completed: completed,
                appWasMutated: appWasMutated,
                snapshot: snapshot,
                reason: "compensation disabled override mismatch"
            )
        }
    }

    private static func compensationMismatch(
        original: AhaKeyReleaseInstallError?,
        compensation: AhaKeyReleaseInstallError,
        completed: [AhaKeyReleaseInstallStep],
        appWasMutated: Bool,
        snapshot: AhaKeyReleaseHostSnapshot,
        reason: String
    ) -> AhaKeyReleaseInstallError {
        if let original {
            return .blocked(
                originalApplyError: original,
                compensationError: compensation,
                completedSteps: completed,
                appWasMutated: appWasMutated,
                snapshot: snapshot,
                reason: reason
            )
        }
        return compensation
    }

    private static func restoreDisabledOverrides(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        identity: AhaKeyReleaseIdentity
    ) throws {
        try host.setLaunchdDisabled(
            label: identity.agentLaunchdLabel,
            disabled: plan.previousDisabledOverrides.officialDisabled
        )
        try host.setLaunchdDisabled(
            label: identity.hilLaunchdLabel,
            disabled: plan.previousDisabledOverrides.hilDisabled
        )
    }
}
