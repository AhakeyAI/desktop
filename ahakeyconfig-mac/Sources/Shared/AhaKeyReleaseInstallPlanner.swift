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

    public init(
        applicationsAppPath: String,
        backupAppPath: String,
        launchAgentsDirectory: String,
        launchAgentPlistPath: String,
        logPath: String,
        socketPath: String,
        userConfigDirectory: String,
        hookPaths: [String],
        permitsSystemApplicationsInstall: Bool = false
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
    }

    public var stagingAppPath: String {
        applicationsAppPath + ".ahakey-staging"
    }

    public var allowedRoots: [String] {
        let destParent = (applicationsAppPath as NSString).deletingLastPathComponent
        let backupParent = (backupAppPath as NSString).deletingLastPathComponent
        let configParent = (userConfigDirectory as NSString).deletingLastPathComponent
        return Array(Set([
            destParent,
            backupParent,
            launchAgentsDirectory,
            configParent,
            userConfigDirectory,
        ]))
    }

    public var preservedPaths: [String] {
        [userConfigDirectory] + hookPaths
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
            ],
            permitsSystemApplicationsInstall: false
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
            permitsSystemApplicationsInstall: true
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

public struct AhaKeyReleaseHostSnapshot: Equatable, Sendable {
    public var darwinMajor: Int
    public var appInstalled: Bool
    public var loadedLaunchdLabels: Set<String>
    public var loginItemRegistered: Bool
    public var preservedPathExists: [String: Bool]

    public init(
        darwinMajor: Int,
        appInstalled: Bool,
        loadedLaunchdLabels: Set<String>,
        loginItemRegistered: Bool = false,
        preservedPathExists: [String: Bool] = [:]
    ) {
        self.darwinMajor = darwinMajor
        self.appInstalled = appInstalled
        self.loadedLaunchdLabels = loadedLaunchdLabels
        self.loginItemRegistered = loginItemRegistered
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
    case systemMutationNotAllowed
}

public enum AhaKeyReleaseInstallStep: Equatable, Sendable {
    case bootout(label: String)
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
    case verifyCleanUninstall
}

public struct AhaKeyReleaseInstallPlan: Equatable, Sendable {
    public let request: AhaKeyReleaseInstallRequest
    public let steps: [AhaKeyReleaseInstallStep]
    public let preservedPaths: [String]
    public let launchAgentPlist: Data
    public let candidateAppPath: String?
    public let previousLaunchAgentPlist: Data?
    public let previousOwnerLabels: Set<String>
    public let previousLoginItemRegistered: Bool
    public let hadPreviousApp: Bool
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
    case rollbackFailed(String)
    case pathViolation(AhaKeyReleasePathViolation)
}

/// 安装器与测试共用的 host 缝：真实实现走文件原子替换 + 可注入 launchd；测试可完全内存化。
public protocol AhaKeyReleaseInstallHost: AnyObject {
    func snapshot(layout: AhaKeyReleaseInstallLayout) -> AhaKeyReleaseHostSnapshot
    func inspectCandidate(at appPath: String, identity: AhaKeyReleaseIdentity) throws -> AhaKeyReleaseCandidateReport
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
        previousLaunchAgentPlist: Data? = nil,
        safety: AhaKeyReleaseInstallSafety = .sandboxOnly
    ) -> Result<AhaKeyReleaseInstallPlan, AhaKeyReleaseInstallRejection> {
        if snapshot.darwinMajor < identity.minimumDarwinMajor {
            return .failure(.unsupportedMacOS(darwinMajor: snapshot.darwinMajor))
        }
        if layout.permitsSystemApplicationsInstall && !safety.allowSystemMutation {
            return .failure(.systemMutationNotAllowed)
        }

        let preserved = layout.preservedPaths
        let previousOwners = competingLabels(in: snapshot.loadedLaunchdLabels, identity: identity)

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
                previousLaunchAgentPlist: previousLaunchAgentPlist,
                previousOwnerLabels: previousOwners,
                previousLoginItemRegistered: snapshot.loginItemRegistered,
                hadPreviousApp: snapshot.appInstalled
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
                previousLaunchAgentPlist: previousLaunchAgentPlist,
                previousOwnerLabels: previousOwners,
                previousLoginItemRegistered: snapshot.loginItemRegistered,
                hadPreviousApp: snapshot.appInstalled
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
        let snapshot = host.snapshot(layout: layout)
        var inspected: AhaKeyReleaseCandidateReport?
        let previousPlist = host.readFile(at: layout.launchAgentPlistPath)
        switch request {
        case .install(let path), .upgrade(let path):
            do {
                inspected = try host.inspectCandidate(at: path, identity: identity)
            } catch {
                throw AhaKeyReleaseInstallError.rejected(.identityRejected(.candidateNotInspected))
            }
        case .uninstall:
            break
        }
        let planned = AhaKeyReleaseInstallPlanner.plan(
            request: request,
            snapshot: snapshot,
            layout: layout,
            identity: identity,
            candidate: inspected,
            previousLaunchAgentPlist: previousPlist,
            safety: safety
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

public enum AhaKeyReleaseInstallEngine {
    public static func apply(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity = .current,
        safety: AhaKeyReleaseInstallSafety = .sandboxOnly,
        injectFailureAt: AhaKeyReleaseInstallStep? = nil
    ) throws -> AhaKeyReleaseInstallOutcome {
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
            let snap = host.snapshot(layout: layout)
            try verifyTerminalState(plan: plan, snapshot: snap, identity: identity, rolledBack: false)
            return AhaKeyReleaseInstallOutcome(
                completedSteps: completed,
                rolledBack: false,
                loadedLaunchdLabels: snap.loadedLaunchdLabels,
                appInstalled: snap.appInstalled,
                loginItemRegistered: snap.loginItemRegistered,
                preservedPaths: plan.preservedPaths
            )
        } catch {
            do {
                try rollback(completed: completed, plan: plan, host: host, layout: layout, identity: identity)
            } catch {
                throw AhaKeyReleaseInstallError.rollbackFailed(String(describing: error))
            }
            let snap = host.snapshot(layout: layout)
            do {
                try verifyTerminalState(plan: plan, snapshot: snap, identity: identity, rolledBack: true)
            } catch {
                throw AhaKeyReleaseInstallError.rollbackFailed(String(describing: error))
            }
            if injectFailureAt != nil {
                return AhaKeyReleaseInstallOutcome(
                    completedSteps: completed,
                    rolledBack: true,
                    loadedLaunchdLabels: snap.loadedLaunchdLabels,
                    appInstalled: snap.appInstalled,
                    loginItemRegistered: snap.loginItemRegistered,
                    preservedPaths: plan.preservedPaths
                )
            }
            throw error
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
        identity: AhaKeyReleaseIdentity,
        rolledBack: Bool
    ) throws {
        let owners = AhaKeyReleaseInstallPlanner.competingLabels(
            in: snapshot.loadedLaunchdLabels,
            identity: identity
        )
        if rolledBack {
            if plan.hadPreviousApp {
                if owners != [identity.agentLaunchdLabel] {
                    throw AhaKeyReleaseInstallError.dualOwnerRemaining(owners)
                }
            } else if !owners.isEmpty {
                throw AhaKeyReleaseInstallError.dualOwnerRemaining(owners)
            }
            return
        }
        switch plan.request {
        case .uninstall:
            if !owners.isEmpty {
                throw AhaKeyReleaseInstallError.dualOwnerRemaining(owners)
            }
        case .install, .upgrade:
            if owners != [identity.agentLaunchdLabel] {
                throw AhaKeyReleaseInstallError.dualOwnerRemaining(owners)
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
            try host.writeFile(at: layout.launchAgentPlistPath, data: plan.launchAgentPlist)
        case .bootstrap(let label):
            try host.bootstrap(label: label, plistPath: layout.launchAgentPlistPath)
        case .restorePreviousLaunchAgent:
            try restorePlist(plan: plan, host: host, layout: layout)
        case .removeLaunchAgent:
            if host.itemExists(at: layout.launchAgentPlistPath) {
                try host.removeTree(layout.launchAgentPlistPath)
            }
        case .registerLoginItem:
            try host.registerLoginItem()
        case .unregisterLoginItem:
            try host.unregisterLoginItem()
        case .restoreApp:
            try restoreApp(host: host, layout: layout)
        case .removeApp:
            try setAsideInstalledApp(plan: plan, host: host, layout: layout)
        case .removeBackup:
            if host.itemExists(at: layout.backupAppPath) {
                try host.removeTree(layout.backupAppPath)
            }
        case .verifySingleOwner, .verifyCleanUninstall:
            let snap = host.snapshot(layout: layout)
            try verifyTerminalState(
                plan: plan,
                snapshot: snap,
                identity: identity,
                rolledBack: false
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
            layout: layout
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
        layout: AhaKeyReleaseInstallLayout
    ) throws {
        do {
            try AhaKeyReleasePathGuard.validateReplacement(
                source: source,
                destination: destination,
                backup: backup,
                staging: staging,
                allowedRoots: layout.allowedRoots,
                permitsApplicationsDestination: layout.permitsSystemApplicationsInstall,
                itemExists: host.itemExists(at:),
                resolve: host.resolvedPath,
                isSymlink: host.isSymlink
            )
        } catch let violation as AhaKeyReleasePathViolation {
            throw AhaKeyReleaseInstallError.pathViolation(violation)
        }
    }

    private static func restoreApp(host: AhaKeyReleaseInstallHost, layout: AhaKeyReleaseInstallLayout) throws {
        let scratch = layout.applicationsAppPath + ".ahakey-rollback-scratch"
        guard host.itemExists(at: layout.backupAppPath) else {
            if host.itemExists(at: layout.applicationsAppPath) {
                try host.removeTree(layout.applicationsAppPath)
            }
            return
        }
        try host.replaceDirectoryAtomically(
            from: layout.backupAppPath,
            to: layout.applicationsAppPath,
            backup: scratch,
            staging: layout.stagingAppPath
        )
        if host.itemExists(at: scratch) {
            try host.removeTree(scratch)
        }
        if host.itemExists(at: layout.backupAppPath) {
            try host.removeTree(layout.backupAppPath)
        }
    }

    private static func restorePlist(
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout
    ) throws {
        if let previous = plan.previousLaunchAgentPlist {
            try host.writeFile(at: layout.launchAgentPlistPath, data: previous)
        } else if host.itemExists(at: layout.launchAgentPlistPath) {
            try host.removeTree(layout.launchAgentPlistPath)
        }
    }

    private static func rollback(
        completed: [AhaKeyReleaseInstallStep],
        plan: AhaKeyReleaseInstallPlan,
        host: AhaKeyReleaseInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        identity: AhaKeyReleaseIdentity
    ) throws {
        if completed.contains(.registerLoginItem) || host.snapshot(layout: layout).loginItemRegistered {
            if !plan.previousLoginItemRegistered {
                try host.unregisterLoginItem()
            }
        }
        try host.bootout(label: identity.agentLaunchdLabel)
        for extra in AhaKeyReleaseInstallPlanner.competingLabels(
            in: host.snapshot(layout: layout).loadedLaunchdLabels,
            identity: identity
        ) where extra != identity.agentLaunchdLabel {
            try host.bootout(label: extra)
        }

        if plan.hadPreviousApp {
            try restoreApp(host: host, layout: layout)
            try restorePlist(plan: plan, host: host, layout: layout)
            try host.bootstrap(label: identity.agentLaunchdLabel, plistPath: layout.launchAgentPlistPath)
            if plan.previousLoginItemRegistered {
                try host.registerLoginItem()
            }
        } else {
            if completed.contains(.writeLaunchAgent) || host.itemExists(at: layout.launchAgentPlistPath) {
                try restorePlist(plan: plan, host: host, layout: layout)
            }
            if host.itemExists(at: layout.applicationsAppPath) {
                try host.removeTree(layout.applicationsAppPath)
            }
            if host.itemExists(at: layout.backupAppPath) {
                try host.removeTree(layout.backupAppPath)
            }
            if host.itemExists(at: layout.stagingAppPath) {
                try host.removeTree(layout.stagingAppPath)
            }
            if plan.previousLoginItemRegistered {
                try host.registerLoginItem()
            }
        }
    }
}
