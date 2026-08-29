import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyReleaseInstallPlannerTests: XCTestCase {

    private let identity = AhaKeyReleaseIdentity.current

    func testIdentityMatchesProductionXPCPeerPolicy() {
        XCTAssertEqual(identity.teamIdentifier, AhaKeyRuntimeXPCPeerPolicy.productionTeamIdentifier)
        XCTAssertTrue(AhaKeyRuntimeXPCPeerPolicy.productionAllowedSigningIdentifiers.contains(identity.signingIdentifier))
        XCTAssertEqual(identity.bundleIdentifier, "lab.jawa.ahakeyconfig")
        XCTAssertEqual(identity.machServiceName, "lab.jawa.ahakeyconfig.runtime")
        XCTAssertEqual(identity.agentLaunchdLabel, "lab.jawa.ahakeyconfig.agent")
        XCTAssertEqual(identity.minimumDarwinMajor, 22)
        XCTAssertEqual(identity.productVersion, "0.2.0")
        XCTAssertTrue(identity.developerIDRequirement.contains(identity.teamIdentifier))
        XCTAssertTrue(identity.developerIDRequirement.contains(identity.signingIdentifier))
    }

    func testLaunchAgentPlistDeclaresMachService() throws {
        let plist = try identity.launchAgentPlist(
            agentBinaryPath: "/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent",
            socketPath: "/tmp/ahakey.sock",
            logPath: "/tmp/agent.log"
        )
        XCTAssertTrue(identity.launchAgentDeclaresMachService(plist))
        let text = String(data: plist, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("MachServices"))
        XCTAssertTrue(text.contains(identity.machServiceName))
        XCTAssertFalse(text.contains("lab.jawa.ahakeyconfig.agent.hil"))
    }

    func testUnsignedCandidateChecklistReady() throws {
        let plist = try identity.launchAgentPlist(
            agentBinaryPath: "/tmp/agent", socketPath: "/tmp/s", logPath: "/tmp/l"
        )
        let report = AhaKeyReleaseCandidateReport(
            bundleIdentifier: identity.bundleIdentifier,
            agentBinaryPresent: true,
            launchAgentPlist: plist,
            signedWithDeveloperID: false
        )
        XCTAssertEqual(AhaKeyReleaseSigningChecklist.check(report), .unsignedCandidateReady)
    }

    func testSignedCandidateWithWrongTeamIsRejected() throws {
        let plist = try identity.launchAgentPlist(
            agentBinaryPath: "/tmp/agent", socketPath: "/tmp/s", logPath: "/tmp/l"
        )
        let report = AhaKeyReleaseCandidateReport(
            bundleIdentifier: identity.bundleIdentifier,
            agentBinaryPresent: true,
            launchAgentPlist: plist,
            teamIdentifier: "UNKNOWNTEAM",
            signingIdentifier: identity.signingIdentifier,
            signedWithDeveloperID: true
        )
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.teamIdentifierMismatch(found: "UNKNOWNTEAM"))
        )
    }

    func testMacOS12IsRejectedWithoutMutatingHost() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 21
        host.preserved["config"] = "keep"
        let layout = layout(root: "/sandbox")
        let snapshot = host.snapshot(layout: layout)
        let result = AhaKeyReleaseInstallPlanner.plan(
            request: .install(candidateAppPath: "/candidate.app"),
            snapshot: snapshot,
            layout: layout
        )
        guard case .failure(.unsupportedMacOS(let major)) = result else {
            return XCTFail("macOS 12 必须拒绝")
        }
        XCTAssertEqual(major, 21)
        XCTAssertFalse(host.appInstalled)
        XCTAssertTrue(host.loaded.isEmpty)
        XCTAssertEqual(host.preserved["config"], "keep")
        XCTAssertTrue(host.writes.isEmpty)
    }

    func testFreshInstallRegistersSingleOwnerAndPreservesHooks() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        host.candidateReport = try validCandidate()
        host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"] = "store"
        host.preserved["/sandbox/Home/.cursor/hooks.json"] = "third-party"
        let layout = self.layout(root: "/sandbox")
        let plan = try unwrapPlan(.install(candidateAppPath: "/candidate.app"), host: host, layout: layout)
        XCTAssertTrue(plan.steps.contains(.registerLoginItem))
        XCTAssertTrue(identity.launchAgentDeclaresMachService(plan.launchAgentPlist))
        let outcome = try AhaKeyReleaseInstallEngine.apply(plan: plan, host: host, layout: layout)
        XCTAssertFalse(outcome.rolledBack)
        XCTAssertTrue(outcome.appInstalled)
        XCTAssertTrue(outcome.loginItemRegistered)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertEqual(host.preserved["/sandbox/Home/.cursor/hooks.json"], "third-party")
        XCTAssertEqual(host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"], "store")
    }

    func testUpgradeBootsOutHILAndOldAgentThenLeavesOneOwner() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 23
        host.appInstalled = true
        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.candidateReport = try validCandidate()
        host.files[layout(root: "/sandbox").launchAgentPlistPath] = Data("old-plist".utf8)
        let layout = self.layout(root: "/sandbox")
        let previous = host.readFile(at: layout.launchAgentPlistPath)
        let plan = try unwrapPlan(
            .upgrade(candidateAppPath: "/candidate.app"),
            host: host,
            layout: layout,
            previous: previous
        )
        XCTAssertTrue(plan.steps.contains(.bootout(label: identity.hilLaunchdLabel)))
        XCTAssertTrue(plan.steps.contains(.backupExistingApp))
        let outcome = try AhaKeyReleaseInstallEngine.apply(plan: plan, host: host, layout: layout)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertFalse(outcome.loadedLaunchdLabels.contains(identity.hilLaunchdLabel))
        XCTAssertTrue(identity.launchAgentDeclaresMachService(host.files[layout.launchAgentPlistPath] ?? Data()))
    }

    func testInjectedFailureAfterInstallAppRollsBackFreshInstall() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        host.candidateReport = try validCandidate()
        host.preserved["/sandbox/Home/.claude/settings.json"] = "hooks"
        let layout = self.layout(root: "/sandbox")
        let plan = try unwrapPlan(.install(candidateAppPath: "/candidate.app"), host: host, layout: layout)
        let outcome = try AhaKeyReleaseInstallEngine.apply(
            plan: plan,
            host: host,
            layout: layout,
            injectFailureAt: .installApp
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertFalse(outcome.appInstalled)
        XCTAssertFalse(host.loginItemRegistered)
        XCTAssertTrue(outcome.loadedLaunchdLabels.isEmpty)
        XCTAssertEqual(host.preserved["/sandbox/Home/.claude/settings.json"], "hooks")
        XCTAssertNil(host.files[layout.launchAgentPlistPath])
    }

    func testInjectedFailureDuringUpgradeRestoresPreviousOwner() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        host.appInstalled = true
        host.loaded = [identity.agentLaunchdLabel]
        host.candidateReport = try validCandidate()
        let layout = self.layout(root: "/sandbox")
        let previousPlist = Data("previous-agent-plist".utf8)
        host.files[layout.launchAgentPlistPath] = previousPlist
        let plan = try unwrapPlan(
            .upgrade(candidateAppPath: "/candidate.app"),
            host: host,
            layout: layout,
            previous: previousPlist
        )
        let outcome = try AhaKeyReleaseInstallEngine.apply(
            plan: plan,
            host: host,
            layout: layout,
            injectFailureAt: .writeLaunchAgent
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertTrue(outcome.appInstalled)
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], previousPlist)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertFalse(host.trees.contains(layout.backupAppPath))
    }

    func testUninstallRemovesAppAndAgentButKeepsUserConfigAndHooks() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        host.appInstalled = true
        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.loginItemRegistered = true
        host.files[layout(root: "/sandbox").launchAgentPlistPath] = Data("plist".utf8)
        host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"] = "keep-store"
        host.preserved["/sandbox/Home/.kimi/config.toml"] = "keep-hook"
        let layout = self.layout(root: "/sandbox")
        let plan = try unwrapPlan(.uninstall, host: host, layout: layout)
        XCTAssertTrue(plan.steps.contains(.removeApp))
        XCTAssertTrue(plan.steps.contains(.unregisterLoginItem))
        let outcome = try AhaKeyReleaseInstallEngine.apply(plan: plan, host: host, layout: layout)
        XCTAssertFalse(outcome.appInstalled)
        XCTAssertTrue(outcome.loadedLaunchdLabels.isEmpty)
        XCTAssertFalse(host.loginItemRegistered)
        XCTAssertNil(host.files[layout.launchAgentPlistPath])
        XCTAssertEqual(host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"], "keep-store")
        XCTAssertEqual(host.preserved["/sandbox/Home/.kimi/config.toml"], "keep-hook")
    }

    func testMissingAgentBinaryRejectedBeforeAnyInstallStep() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        let layout = self.layout(root: "/sandbox")
        let bad = AhaKeyReleaseCandidateReport(
            bundleIdentifier: identity.bundleIdentifier,
            agentBinaryPresent: false,
            launchAgentPlist: try identity.launchAgentPlist(
                agentBinaryPath: "/x", socketPath: "/s", logPath: "/l"
            )
        )
        let result = AhaKeyReleaseInstallPlanner.plan(
            request: .install(candidateAppPath: "/candidate.app"),
            snapshot: host.snapshot(layout: layout),
            layout: layout,
            candidate: bad
        )
        guard case .failure(.identityRejected(.missingAgentBinary)) = result else {
            return XCTFail("缺 agent 必须拒绝")
        }
        XCTAssertFalse(host.appInstalled)
    }

    private func layout(root: String) -> AhaKeyReleaseInstallLayout {
        .sandboxed(root: root, identity: identity)
    }

    private func validCandidate() throws -> AhaKeyReleaseCandidateReport {
        let plist = try identity.launchAgentPlist(
            agentBinaryPath: "/candidate.app/Contents/MacOS/ahakeyconfig-agent",
            socketPath: "/s",
            logPath: "/l"
        )
        return AhaKeyReleaseCandidateReport(
            bundleIdentifier: identity.bundleIdentifier,
            agentBinaryPresent: true,
            launchAgentPlist: plist
        )
    }

    private func unwrapPlan(
        _ request: AhaKeyReleaseInstallRequest,
        host: FakeInstallHost,
        layout: AhaKeyReleaseInstallLayout,
        previous: Data? = nil
    ) throws -> AhaKeyReleaseInstallPlan {
        let snapshot = host.snapshot(layout: layout)
        let result = AhaKeyReleaseInstallPlanner.plan(
            request: request,
            snapshot: snapshot,
            layout: layout,
            candidate: host.candidateReport,
            previousLaunchAgentPlist: previous
        )
        switch result {
        case .success(let plan):
            return plan
        case .failure(let rejection):
            XCTFail("unexpected rejection \(rejection)")
            throw AhaKeyReleaseInstallError.rejected(rejection)
        }
    }
}

private final class FakeInstallHost: AhaKeyReleaseInstallHost {
    var darwinMajor = 22
    var appInstalled = false
    var loaded: Set<String> = []
    var loginItemRegistered = false
    var files: [String: Data] = [:]
    var trees: Set<String> = []
    var preserved: [String: String] = [:]
    var writes: [String] = []
    var candidateReport: AhaKeyReleaseCandidateReport?

    func snapshot(layout: AhaKeyReleaseInstallLayout) -> AhaKeyReleaseHostSnapshot {
        var exists: [String: Bool] = [:]
        for path in [layout.userConfigDirectory] + layout.hookPaths {
            exists[path] = preserved[path] != nil
        }
        return AhaKeyReleaseHostSnapshot(
            darwinMajor: darwinMajor,
            appInstalled: appInstalled,
            loadedLaunchdLabels: loaded,
            preservedPathExists: exists
        )
    }

    func inspectCandidate(at appPath: String, identity: AhaKeyReleaseIdentity) -> AhaKeyReleaseCandidateReport {
        candidateReport ?? AhaKeyReleaseCandidateReport(
            bundleIdentifier: identity.bundleIdentifier,
            agentBinaryPresent: true,
            launchAgentPlist: try? identity.launchAgentPlist(
                agentBinaryPath: identity.agentBinaryPath(inApp: appPath),
                socketPath: "/s",
                logPath: "/l"
            )
        )
    }

    func copyTree(from: String, to: String) throws {
        trees.insert(to)
        if to.hasSuffix(".app") && !to.contains(".ahakey-backup") {
            appInstalled = true
        }
        if from.hasSuffix(".ahakey-backup") {
            appInstalled = true
        }
    }

    func removeTree(_ path: String) throws {
        trees.remove(path)
        files[path] = nil
        if path.hasSuffix(".app") && !path.contains(".ahakey-backup") {
            appInstalled = false
        }
    }

    func writeFile(at path: String, data: Data) throws {
        files[path] = data
        writes.append(path)
    }

    func readFile(at path: String) -> Data? {
        files[path]
    }

    func bootout(label: String) throws {
        loaded.remove(label)
    }

    func bootstrap(label: String, plistPath: String) throws {
        _ = plistPath
        loaded.insert(label)
    }

    func registerLoginItem() throws {
        loginItemRegistered = true
    }

    func unregisterLoginItem() throws {
        loginItemRegistered = false
    }
}
