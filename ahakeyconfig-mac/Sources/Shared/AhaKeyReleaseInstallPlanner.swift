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

    public init(
        applicationsAppPath: String,
        backupAppPath: String,
        launchAgentsDirectory: String,
        launchAgentPlistPath: String,
        logPath: String,
        socketPath: String,
        userConfigDirectory: String,
        hookPaths: [String]
    ) {
        self.applicationsAppPath = applicationsAppPath
        self.backupAppPath = backupAppPath
        self.launchAgentsDirectory = launchAgentsDirectory
        self.launchAgentPlistPath = launchAgentPlistPath
        self.logPath = logPath
        self.socketPath = socketPath
        self.userConfigDirectory = userConfigDirectory
        self.hookPaths = hookPaths
    }

    /// 沙箱布局：全部落在 `root` 下，供可注入测试使用。
    public static func sandboxed(root: String, identity: AhaKeyReleaseIdentity = .current) -> Self {
        let launchAgents = (root as NSString).appendingPathComponent("LaunchAgents")
        let home = (root as NSString).appendingPathComponent("Home")
        return Self(
            applicationsAppPath: (root as NSString).appendingPathComponent("Applications/\(identity.appBundleFileName)"),
            backupAppPath: (root as NSString).appendingPathComponent("Applications/\(identity.appBundleFileName).ahakey-backup"),
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
            ]
        )
    }
}

public struct AhaKeyReleaseHostSnapshot: Equatable, Sendable {
    public var darwinMajor: Int
    public var appInstalled: Bool
    public var loadedLaunchdLabels: Set<String>
    public var preservedPathExists: [String: Bool]

    public init(
        darwinMajor: Int,
        appInstalled: Bool,
        loadedLaunchdLabels: Set<String>,
        preservedPathExists: [String: Bool] = [:]
    ) {
        self.darwinMajor = darwinMajor
        self.appInstalled = appInstalled
        self.loadedLaunchdLabels = loadedLaunchdLabels
        self.preservedPathExists = preservedPathExists
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
}

public enum AhaKeyReleaseInstallStep: Equatable, Sendable {
    case bootout(label: String)
    case backupExistingApp
    case installApp
    case writeLaunchAgent
    case bootstrap(label: String)
    case restorePreviousLaunchAgent
    case removeLaunchAgent
    case registerLoginItem
    case unregisterLoginItem
    case restoreApp
    case removeApp
    case removeBackup
    case verifySingleOwner
}

public struct AhaKeyReleaseInstallPlan: Equatable, Sendable {
    public let request: AhaKeyReleaseInstallRequest
    public let steps: [AhaKeyReleaseInstallStep]
    public let preservedPaths: [String]
    public let launchAgentPlist: Data
    public let candidateAppPath: String?
    public let previousLaunchAgentPlist: Data?
}

public struct AhaKeyReleaseInstallOutcome: Equatable, Sendable {
    public let completedSteps: [AhaKeyReleaseInstallStep]
    public let rolledBack: Bool
    public let loadedLaunchdLabels: Set<String>
    public let appInstalled: Bool
    public let loginItemRegistered: Bool
    public let preservedPaths: [String]
}

public enum AhaKeyReleaseInstallError: Error, Equatable {
    case rejected(AhaKeyReleaseInstallRejection)
    case injectedFailure(AhaKeyReleaseInstallStep)
    case hostFailure(String)
    case dualOwnerRemaining(Set<String>)
}

/// 安装器与测试共用的 host 缝：真实实现可调 launchctl / SMAppService，测试注入内存适配器。
public protocol AhaKeyReleaseInstallHost: AnyObject {
    func snapshot(layout: AhaKeyReleaseInstallLayout) -> AhaKeyReleaseHostSnapshot
    func inspectCandidate(at appPath: String, identity: AhaKeyReleaseIdentity) -> AhaKeyReleaseCandidateReport
    func copyTree(from: String, to: String) throws
    func removeTree(_ path: String) throws
    func writeFile(at path: String, data: Data) throws
    func readFile(at path: String) -> Data?
    func bootout(label: String) throws
    func bootstrap(label: String, plistPath: String) throws
    func registerLoginItem() throws
    func unregisterLoginItem() throws
}

public enum AhaKeyReleaseInstallPlanner {
    public static func competingLabels(
        in loaded: Set<String>,
        identity: AhaKeyReleaseIdentity = .current
    ) -> Set<String> {
        loaded.filter { label in
            label == identity.hilLaunchdLabel
                || (label.hasPrefix("lab.jawa.ahakeyconfig.") && label != identity.agentLaunchdLabel)
                || label == identity.agentLaunchdLabel
        }
    }

    public static func plan(
        request: AhaKeyReleaseInstallRequest,
        snapshot: AhaKeyReleaseHostSnapshot,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity = .current,
        candidate: AhaKeyReleaseCandidateReport? = nil,
        previousLaunchAgentPlist: Data? = nil
    ) -> Result<AhaKeyReleaseInstallPlan, AhaKeyReleaseInstallRejection> {
        if snapshot.darwinMajor < identity.minimumDarwinMajor {
            return .failure(.unsupportedMacOS(darwinMajor: snapshot.darwinMajor))
        }

        let preserved = [layout.userConfigDirectory] + layout.hookPaths

        switch request {
        case .uninstall:
            var steps: [AhaKeyReleaseInstallStep] = competingLabels(in: snapshot.loadedLaunchdLabels, identity: identity)
                .sorted()
                .map { .bootout(label: $0) }
            steps.append(.unregisterLoginItem)
            steps.append(.removeLaunchAgent)
            if snapshot.appInstalled {
                steps.append(.removeApp)
            }
            let emptyPlist = Data()
            return .success(AhaKeyReleaseInstallPlan(
                request: request,
                steps: steps,
                preservedPaths: preserved,
                launchAgentPlist: emptyPlist,
                candidateAppPath: nil,
                previousLaunchAgentPlist: previousLaunchAgentPlist
            ))

        case .install(let candidatePath), .upgrade(let candidatePath):
            if candidatePath.isEmpty {
                return .failure(.missingCandidate)
            }
            if let candidate {
                if case .rejected(let reason) = AhaKeyReleaseSigningChecklist.check(candidate, identity: identity) {
                    return .failure(.identityRejected(reason))
                }
            }
            let agentPath = identity.agentBinaryPath(inApp: layout.applicationsAppPath)
            guard let plist = try? identity.launchAgentPlist(
                agentBinaryPath: agentPath,
                socketPath: layout.socketPath,
                logPath: layout.logPath
            ) else {
                return .failure(.identityRejected(.machServiceMissing))
            }

            var steps: [AhaKeyReleaseInstallStep] = competingLabels(in: snapshot.loadedLaunchdLabels, identity: identity)
                .sorted()
                .map { .bootout(label: $0) }
            if snapshot.appInstalled {
                steps.append(.backupExistingApp)
            }
            steps.append(.installApp)
            steps.append(.writeLaunchAgent)
            steps.append(.bootstrap(label: identity.agentLaunchdLabel))
            steps.append(.registerLoginItem)
            steps.append(.verifySingleOwner)
            if snapshot.appInstalled {
                steps.append(.removeBackup)
            }
            return .success(AhaKeyReleaseInstallPlan(
                request: request,
                steps: steps,
                preservedPaths: preserved,
                launchAgentPlist: plist,
                candidateAppPath: candidatePath,
                previousLaunchAgentPlist: previousLaunchAgentPlist
            ))
        }
    }
}

public enum AhaKeyReleaseInstallEngine {
    public static func apply(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity = .current,
        injectFailureAt: AhaKeyReleaseInstallStep? = nil
    ) throws -> AhaKeyReleaseInstallOutcome {
        var completed: [AhaKeyReleaseInstallStep] = []
        do {
            for step in plan.steps {
                try perform(step, plan: plan, host: host, layout: layout, identity: identity)
                completed.append(step)
                if step == injectFailureAt {
                    throw AhaKeyReleaseInstallError.injectedFailure(step)
                }
            }
            let snap = host.snapshot(layout: layout)
            return AhaKeyReleaseInstallOutcome(
                completedSteps: completed,
                rolledBack: false,
                loadedLaunchdLabels: snap.loadedLaunchdLabels,
                appInstalled: snap.appInstalled,
                loginItemRegistered: loginItemFrom(steps: completed, undone: false),
                preservedPaths: plan.preservedPaths
            )
        } catch {
            try rollback(completed: completed, plan: plan, host: host, layout: layout, identity: identity)
            let snap = host.snapshot(layout: layout)
            if injectFailureAt != nil {
                return AhaKeyReleaseInstallOutcome(
                    completedSteps: completed,
                    rolledBack: true,
                    loadedLaunchdLabels: snap.loadedLaunchdLabels,
                    appInstalled: snap.appInstalled,
                    loginItemRegistered: false,
                    preservedPaths: plan.preservedPaths
                )
            }
            throw error
        }
    }

    private static func loginItemFrom(steps: [AhaKeyReleaseInstallStep], undone: Bool) -> Bool {
        if undone { return false }
        return steps.contains(.registerLoginItem) && !steps.contains(.unregisterLoginItem)
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
        case .backupExistingApp:
            try host.copyTree(from: layout.applicationsAppPath, to: layout.backupAppPath)
        case .installApp:
            guard let candidate = plan.candidateAppPath else {
                throw AhaKeyReleaseInstallError.hostFailure("missing candidate")
            }
            try host.copyTree(from: candidate, to: layout.applicationsAppPath)
        case .writeLaunchAgent:
            try host.writeFile(at: layout.launchAgentPlistPath, data: plan.launchAgentPlist)
        case .bootstrap(let label):
            try host.bootstrap(label: label, plistPath: layout.launchAgentPlistPath)
        case .restorePreviousLaunchAgent:
            if let previous = plan.previousLaunchAgentPlist {
                try host.writeFile(at: layout.launchAgentPlistPath, data: previous)
            } else {
                try host.removeTree(layout.launchAgentPlistPath)
            }
        case .removeLaunchAgent:
            try host.removeTree(layout.launchAgentPlistPath)
        case .registerLoginItem:
            try host.registerLoginItem()
        case .unregisterLoginItem:
            try host.unregisterLoginItem()
        case .restoreApp:
            try host.copyTree(from: layout.backupAppPath, to: layout.applicationsAppPath)
        case .removeApp:
            try host.removeTree(layout.applicationsAppPath)
        case .removeBackup:
            try host.removeTree(layout.backupAppPath)
        case .verifySingleOwner:
            let snap = host.snapshot(layout: layout)
            let owners = snap.loadedLaunchdLabels.filter {
                $0.hasPrefix("lab.jawa.ahakeyconfig.")
            }
            if owners != [identity.agentLaunchdLabel] {
                throw AhaKeyReleaseInstallError.dualOwnerRemaining(owners)
            }
            _ = identity
        }
    }

    private static func rollback(
        completed: [AhaKeyReleaseInstallStep],
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity
    ) throws {
        if completed.contains(.registerLoginItem) {
            try? host.unregisterLoginItem()
        }
        try? host.bootout(label: identity.agentLaunchdLabel)

        if let previous = plan.previousLaunchAgentPlist {
            if completed.contains(.installApp) || completed.contains(.backupExistingApp) {
                try? host.copyTree(from: layout.backupAppPath, to: layout.applicationsAppPath)
            }
            try? host.writeFile(at: layout.launchAgentPlistPath, data: previous)
            try? host.bootstrap(label: identity.agentLaunchdLabel, plistPath: layout.launchAgentPlistPath)
        } else {
            if completed.contains(.writeLaunchAgent) {
                try? host.removeTree(layout.launchAgentPlistPath)
            }
            if completed.contains(.installApp) {
                try? host.removeTree(layout.applicationsAppPath)
            }
        }
        if completed.contains(.backupExistingApp) {
            try? host.removeTree(layout.backupAppPath)
        }
    }
}
