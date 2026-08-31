import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyReleaseInstallPlannerTests: XCTestCase {

    private let identity = AhaKeyReleaseIdentity.current

    func testEmbeddedIdentityMatchesPackagingJSONAndXPCPolicy() throws {
        XCTAssertEqual(identity.teamIdentifier, AhaKeyRuntimeXPCPeerPolicy.productionTeamIdentifier)
        XCTAssertTrue(AhaKeyRuntimeXPCPeerPolicy.productionAllowedSigningIdentifiers.contains(identity.signingIdentifier))
        XCTAssertEqual(identity.bundleIdentifier, "lab.jawa.ahakeyconfig")
        XCTAssertEqual(identity.machServiceName, "lab.jawa.ahakeyconfig.runtime")
        XCTAssertEqual(identity.agentLaunchdLabel, "lab.jawa.ahakeyconfig.agent")
        XCTAssertEqual(identity.minimumDarwinMajor, 22)
        XCTAssertEqual(identity.productVersion, "0.2.0")
        XCTAssertTrue(identity.developerIDRequirement.contains(identity.teamIdentifier))
        XCTAssertTrue(identity.developerIDRequirement.contains(identity.signingIdentifier))

        let packaging = packagingIdentityURL()
        let fileObject = try JSONSerialization.jsonObject(with: Data(contentsOf: packaging))
        let embeddedObject = try JSONSerialization.jsonObject(with: Data(AhaKeyReleaseIdentityDocument.json.utf8))
        XCTAssertEqual(fileObject as? NSDictionary, embeddedObject as? NSDictionary)
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
        XCTAssertEqual(AhaKeyReleaseSigningChecklist.check(try validCandidate()), .unsignedCandidateReady)
    }

    func testNilCandidateIsRejected() {
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(nil),
            .rejected(.candidateNotInspected)
        )
    }

    func testUnsignedCandidateMissingSigningIdentifierIsRejected() throws {
        var report = try validCandidate()
        report.signingIdentifier = nil
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.missingSigningIdentifier)
        )
    }

    func testUnsignedCandidateWithUnknownKindIsRejected() throws {
        var report = try validCandidate()
        report.signatureKind = .unknown
        report.agentSignatureKind = .unknown
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.unsignedCandidateNotAdHoc)
        )
    }

    func testUnsignedCandidateWithTeamIdIsRejected() throws {
        var report = try validCandidate()
        report.teamIdentifier = identity.teamIdentifier
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.unexpectedDeveloperID)
        )
    }

    func testDeveloperIDMissingTeamIsRejected() throws {
        var report = try validCandidate()
        report.signatureKind = .developerID
        report.agentSignatureKind = .developerID
        report.teamIdentifier = nil
        report.agentTeamIdentifier = nil
        report.signingIdentifier = identity.signingIdentifier
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.missingTeamIdentifier)
        )
    }

    func testDeveloperIDMissingSigningIdentifierIsRejected() throws {
        var report = try validCandidate()
        report.signatureKind = .developerID
        report.agentSignatureKind = .developerID
        report.teamIdentifier = identity.teamIdentifier
        report.agentTeamIdentifier = identity.teamIdentifier
        report.signingIdentifier = "  "
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.missingSigningIdentifier)
        )
    }

    func testSignedCandidateWithWrongTeamIsRejected() throws {
        var report = try validCandidate()
        report.signatureKind = .developerID
        report.agentSignatureKind = .developerID
        report.teamIdentifier = "UNKNOWNTEAM"
        report.agentTeamIdentifier = "UNKNOWNTEAM"
        report.signingIdentifier = identity.signingIdentifier
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.teamIdentifierMismatch(found: "UNKNOWNTEAM"))
        )
    }

    func testPlanWithoutInspectedCandidateIsRejected() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        let layout = layout(root: "/sandbox")
        let result = AhaKeyReleaseInstallPlanner.plan(
            request: .install(candidateAppPath: candidatePath()),
            snapshot: try host.snapshot(layout: layout),
            layout: layout,
            candidate: nil
        )
        guard case .failure(.identityRejected(.candidateNotInspected)) = result else {
            return XCTFail("未 inspect 的候选必须拒绝")
        }
    }

    func testInstallerInspectsInsteadOfTrustingCaller() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        host.candidateReport = nil
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .install(candidateAppPath: candidatePath()),
                host: host,
                layout: layout(root: "/sandbox")
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.identityRejected(.candidateNotInspected))
            )
        }
        XCTAssertFalse(host.itemExists(at: layout(root: "/sandbox").applicationsAppPath))
    }

    func testMacOS12IsRejectedWithoutMutatingHost() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 21
        host.preserved["config"] = "keep"
        let layout = layout(root: "/sandbox")
        let snapshot = try host.snapshot(layout: layout)
        let result = AhaKeyReleaseInstallPlanner.plan(
            request: .install(candidateAppPath: candidatePath()),
            snapshot: snapshot,
            layout: layout,
            candidate: try validCandidate()
        )
        guard case .failure(.unsupportedMacOS(let major)) = result else {
            return XCTFail("macOS 12 必须拒绝")
        }
        XCTAssertEqual(major, 21)
        XCTAssertTrue(host.loaded.isEmpty)
        XCTAssertEqual(host.preserved["config"], "keep")
        XCTAssertTrue(host.writes.isEmpty)
    }

    func testProductionLayoutIsBlockedWithoutSystemMutation() throws {
        let result = AhaKeyReleaseInstallPlanner.plan(
            request: .install(candidateAppPath: "/tmp/candidate.app"),
            snapshot: AhaKeyReleaseHostSnapshot(darwinMajor: 22, appInstalled: false, loadedLaunchdLabels: []),
            layout: .production(),
            candidate: try validCandidate(),
            safety: .sandboxOnly
        )
        guard case .failure(.systemMutationNotAllowed) = result else {
            return XCTFail("未授权系统突变时必须拒绝 /Applications 布局")
        }
    }

    func testFreshInstallRegistersSingleOwnerAndPreservesHooks() throws {
        let host = preparedHost()
        host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"] = "store"
        host.preserved["/sandbox/Home/.cursor/hooks.json"] = "third-party"
        let layout = self.layout(root: "/sandbox")
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .install(candidateAppPath: candidatePath()),
            host: host,
            layout: layout
        )
        XCTAssertFalse(outcome.rolledBack)
        XCTAssertTrue(outcome.appInstalled)
        XCTAssertTrue(outcome.loginItemRegistered)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertEqual(host.preserved["/sandbox/Home/.cursor/hooks.json"], "third-party")
        XCTAssertEqual(host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"], "store")
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["new-binary"])
    }

    func testUpgradeReplacesStaleFilesInsteadOfCopyingOver() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["stale-extra", "old-binary"]
        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.files[layout.launchAgentPlistPath] = Data("old-plist".utf8)
        host.files[layout.hilLaunchAgentPlistPath] = Data("hil-plist".utf8)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout
        )
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertFalse(outcome.loadedLaunchdLabels.contains(identity.hilLaunchdLabel))
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["new-binary"])
        XCTAssertFalse(host.trees[layout.applicationsAppPath]?.contains("stale-extra") ?? true)
        XCTAssertNil(host.trees[layout.backupAppPath])
        XCTAssertTrue(identity.launchAgentDeclaresMachService(host.files[layout.launchAgentPlistPath] ?? Data()))
    }

    func testInjectedFailureAfterInstallAppRollsBackFreshInstall() throws {
        let host = preparedHost()
        host.preserved["/sandbox/Home/.claude/settings.json"] = "hooks"
        let layout = self.layout(root: "/sandbox")
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .install(candidateAppPath: candidatePath()),
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
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-binary"]
        host.loaded = [identity.agentLaunchdLabel]
        let previousPlist = Data("previous-agent-plist".utf8)
        host.files[layout.launchAgentPlistPath] = previousPlist
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout,
            injectFailureAt: .writeLaunchAgent
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertTrue(outcome.appInstalled)
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], previousPlist)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["old-binary"])
        XCTAssertNil(host.trees[layout.backupAppPath])
    }

    func testRollbackFailureIsReturnedInsteadOfClaimingSuccess() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-binary"]
        host.loaded = [identity.agentLaunchdLabel]
        host.files[layout.launchAgentPlistPath] = Data("previous".utf8)
        host.failReplaceAfterSuccesses = 1
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: candidatePath()),
                host: host,
                layout: layout,
                injectFailureAt: .installApp
            )
        ) { error in
            guard case .compensationFailed(let original, let compensation, let steps, let mutated, let snap) =
                error as? AhaKeyReleaseInstallError
            else {
                return XCTFail("恢复失败必须保留 original+compensation，不能声称 rolledBack=true，error=\(error)")
            }
            XCTAssertEqual(original, .injectedFailure(.installApp))
            guard case .hostFailure(let message) = compensation else {
                return XCTFail("compensation 必须是 restore 的 hostFailure，got \(compensation)")
            }
            XCTAssertTrue(message.contains("injected replace failure"), message)
            XCTAssertTrue(steps.contains(.installApp))
            XCTAssertTrue(mutated)
            XCTAssertTrue(snap.appInstalled)
        }
    }

    func testUninstallRemovesAppAndAgentButKeepsUserConfigAndHooks() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["installed"]
        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.loginItemRegistered = true
        host.files[layout.launchAgentPlistPath] = Data("plist".utf8)
        host.files[layout.hilLaunchAgentPlistPath] = Data("hil-plist".utf8)
        host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"] = "keep-store"
        host.preserved["/sandbox/Home/.kimi/config.toml"] = "keep-hook"
        let outcome = try AhaKeyReleaseInstaller.run(request: .uninstall, host: host, layout: layout)
        XCTAssertFalse(outcome.appInstalled)
        XCTAssertTrue(outcome.loadedLaunchdLabels.isEmpty)
        XCTAssertFalse(host.loginItemRegistered)
        XCTAssertNil(host.files[layout.launchAgentPlistPath])
        XCTAssertNil(host.files[layout.hilLaunchAgentPlistPath])
        XCTAssertNil(host.trees[layout.applicationsAppPath])
        XCTAssertNil(host.trees[layout.backupAppPath])
        XCTAssertEqual(host.preserved["/sandbox/Home/Library/Application Support/AhaKeyConfig"], "keep-store")
        XCTAssertEqual(host.preserved["/sandbox/Home/.kimi/config.toml"], "keep-hook")
    }

    func testUninstallFailureAfterRemovingAppRestoresBackup() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["installed"]
        host.loaded = [identity.agentLaunchdLabel]
        host.loginItemRegistered = true
        host.files[layout.launchAgentPlistPath] = Data("plist".utf8)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .uninstall,
            host: host,
            layout: layout,
            injectFailureAt: .removeApp
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertTrue(outcome.appInstalled)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["installed"])
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertTrue(host.loginItemRegistered)
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], Data("plist".utf8))
    }

    func testMissingAgentBinaryRejectedBeforeAnyInstallStep() throws {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        let layout = self.layout(root: "/sandbox")
        var bad = try validCandidate()
        bad.agentBinaryPresent = false
        host.candidateReport = bad
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .install(candidateAppPath: candidatePath()),
                host: host,
                layout: layout
            )
        )
        XCTAssertNil(host.trees[layout.applicationsAppPath])
    }

    func testSourceEqualsDestinationIsRejected() throws {
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateReplacement(
                source: "/sandbox/Applications/AhaKey Studio.app",
                destination: "/sandbox/Applications/AhaKey Studio.app",
                backup: "/sandbox/Applications/AhaKey Studio.app.ahakey-backup",
                staging: "/sandbox/Applications/AhaKey Studio.app.ahakey-staging",
                allowedRoots: ["/sandbox/Applications"],
                candidateRoots: ["/sandbox/Applications"],
                permitsApplicationsDestination: false,
                itemExists: { _ in false },
                resolve: { $0 },
                isSymlink: { _ in false }
            )
        )
    }

    func testBackupPreexistsIsRejected() throws {
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateReplacement(
                source: "/tmp/candidate.app",
                destination: "/sandbox/Applications/AhaKey Studio.app",
                backup: "/sandbox/Applications/AhaKey Studio.app.ahakey-backup",
                staging: "/sandbox/Applications/AhaKey Studio.app.ahakey-staging",
                allowedRoots: ["/sandbox/Applications", "/tmp"],
                candidateRoots: ["/tmp"],
                permitsApplicationsDestination: false,
                itemExists: { $0.hasSuffix(".ahakey-backup") },
                resolve: { $0 },
                isSymlink: { _ in false }
            )
        ) { error in
            guard case .backupAlreadyExists = error as? AhaKeyReleasePathViolation else {
                return XCTFail("\(error)")
            }
        }
    }

    func testApplicationsOutputIsRejected() throws {
        XCTAssertThrowsError(try AhaKeyReleasePathGuard.refuseApplicationsOutput("/Applications"))
        XCTAssertThrowsError(try AhaKeyReleasePathGuard.refuseApplicationsOutput("/Applications/AhaKey Studio.app"))
        XCTAssertNoThrow(try AhaKeyReleasePathGuard.refuseApplicationsOutput("/tmp/unsigned-v0.2"))
    }

    func testSymlinkEscapeIsRejected() throws {
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateReplacement(
                source: "/tmp/candidate.app",
                destination: "/sandbox/Applications/AhaKey Studio.app",
                backup: "/sandbox/Applications/AhaKey Studio.app.ahakey-backup",
                staging: "/sandbox/Applications/AhaKey Studio.app.ahakey-staging",
                allowedRoots: ["/sandbox/Applications"],
                candidateRoots: ["/tmp"],
                permitsApplicationsDestination: false,
                itemExists: { _ in false },
                resolve: { path in
                    path == "/sandbox/Applications" ? "/tmp/outside" : path
                },
                isSymlink: { $0 == "/sandbox/Applications" }
            )
        ) { error in
            guard case .pathContainsSymlink = error as? AhaKeyReleasePathViolation else {
                return XCTFail("\(error)")
            }
        }
    }

    func testAppIntegrityFailureIsRejected() throws {
        var report = try validCandidate()
        report.appIntegrityVerified = false
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.appIntegrityFailed)
        )
    }

    func testAgentIntegrityFailureIsRejected() throws {
        var report = try validCandidate()
        report.agentIntegrityVerified = false
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.agentIntegrityFailed)
        )
    }

    func testAgentSigningIdentifierMismatchIsRejected() throws {
        var report = try validCandidate()
        report.agentSigningIdentifier = "other.signing.id"
        XCTAssertEqual(
            AhaKeyReleaseSigningChecklist.check(report),
            .rejected(.agentSigningIdentifierMismatch(found: "other.signing.id"))
        )
    }

    func testFailureAfterFirstBootoutPreservesExactAppTree() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        let exactTree: Set<String> = ["old-binary", "keep-me", "nested/resource"]
        host.trees[layout.applicationsAppPath] = exactTree
        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.loginItemRegistered = true
        let officialPlist = Data("official-before".utf8)
        let hilPlist = Data("hil-before".utf8)
        host.files[layout.launchAgentPlistPath] = officialPlist
        host.files[layout.hilLaunchAgentPlistPath] = hilPlist
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout,
            injectFailureAt: .bootout(label: identity.agentLaunchdLabel)
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], exactTree)
        XCTAssertNil(host.trees[layout.backupAppPath])
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], officialPlist)
        XCTAssertEqual(host.files[layout.hilLaunchAgentPlistPath], hilPlist)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel, identity.hilLaunchdLabel])
        XCTAssertTrue(host.loginItemRegistered)
        XCTAssertTrue(outcome.appInstalled)
    }

    func testRollbackRestoresHilAndOfficialOwners() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-binary"]
        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.loginItemRegistered = false
        let officialPlist = Data("official-prev".utf8)
        let hilPlist = Data("hil-prev".utf8)
        host.files[layout.launchAgentPlistPath] = officialPlist
        host.files[layout.hilLaunchAgentPlistPath] = hilPlist
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout,
            injectFailureAt: .writeLaunchAgent
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["old-binary"])
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], officialPlist)
        XCTAssertEqual(host.files[layout.hilLaunchAgentPlistPath], hilPlist)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel, identity.hilLaunchdLabel])
        XCTAssertFalse(host.loginItemRegistered)
    }

    func testAmbiguousExtraOwnerIsRejectedBeforeMutation() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        let exactTree: Set<String> = ["do-not-touch"]
        host.trees[layout.applicationsAppPath] = exactTree
        host.loaded = [identity.agentLaunchdLabel, identity.agentLaunchdLabel + ".legacy"]
        host.files[layout.launchAgentPlistPath] = Data("official".utf8)
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: candidatePath()),
                host: host,
                layout: layout
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.ambiguousPreviousOwners([
                    identity.agentLaunchdLabel,
                    identity.agentLaunchdLabel + ".legacy",
                ]))
            )
        }
        XCTAssertEqual(host.trees[layout.applicationsAppPath], exactTree)
        XCTAssertEqual(host.loaded, [identity.agentLaunchdLabel, identity.agentLaunchdLabel + ".legacy"])
        XCTAssertEqual(host.writes, [])
    }

    func testMissingOwnerPlistIsRejectedBeforeMutation() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["keep"]
        host.loaded = [identity.hilLaunchdLabel]
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: candidatePath()),
                host: host,
                layout: layout
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.ambiguousPreviousOwners([identity.hilLaunchdLabel]))
            )
        }
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["keep"])
        XCTAssertEqual(host.loaded, [identity.hilLaunchdLabel])
    }

    func testCandidateParentSymlinkIsRejected() throws {
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateReplacement(
                source: "/sandbox/Candidates/nested/candidate.app",
                destination: "/sandbox/Applications/AhaKey Studio.app",
                backup: "/sandbox/Applications/AhaKey Studio.app.ahakey-backup",
                staging: "/sandbox/Applications/AhaKey Studio.app.ahakey-staging",
                allowedRoots: ["/sandbox/Applications"],
                candidateRoots: ["/sandbox/Candidates"],
                permitsApplicationsDestination: false,
                itemExists: { _ in false },
                resolve: { $0 },
                isSymlink: { $0 == "/sandbox/Candidates/nested" }
            )
        ) { error in
            guard case .pathContainsSymlink = error as? AhaKeyReleasePathViolation else {
                return XCTFail("\(error)")
            }
        }
    }

    func testGuardedRemoveDoesNotSelfAuthorizeParent() throws {
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateDestructive(
                "/sandbox/evil/outside.app",
                allowedRoots: ["/sandbox/Applications"],
                permitsApplicationsDestination: false,
                resolve: { $0 },
                isSymlink: { _ in false }
            )
        ) { error in
            guard case .pathEscapesAllowedRoot = error as? AhaKeyReleasePathViolation else {
                return XCTFail("\(error)")
            }
        }
        XCTAssertNoThrow(
            try AhaKeyReleasePathGuard.validateDestructive(
                "/sandbox/Applications/AhaKey Studio.app",
                allowedRoots: ["/sandbox/Applications"],
                permitsApplicationsDestination: false,
                resolve: { $0 },
                isSymlink: { _ in false }
            )
        )
    }

    func testFsyncAfterReplaceRestoresExactAppTree() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        let exactTree: Set<String> = ["old-binary", "keep-me"]
        host.trees[layout.applicationsAppPath] = exactTree
        host.loaded = [identity.agentLaunchdLabel]
        let previousPlist = Data("previous".utf8)
        host.files[layout.launchAgentPlistPath] = previousPlist
        host.failAfterCommittedReplace = true
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], exactTree)
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], previousPlist)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertNil(host.trees[layout.backupAppPath])
    }

    func testFsyncAfterUninstallMoveRestoresExactAppTree() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        let exactTree: Set<String> = ["installed", "keep"]
        host.trees[layout.applicationsAppPath] = exactTree
        host.loaded = [identity.agentLaunchdLabel]
        host.loginItemRegistered = true
        let previousPlist = Data("plist".utf8)
        host.files[layout.launchAgentPlistPath] = previousPlist
        host.failAfterCommittedMove = true
        let outcome = try AhaKeyReleaseInstaller.run(request: .uninstall, host: host, layout: layout)
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], exactTree)
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], previousPlist)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertTrue(host.loginItemRegistered)
    }

    func testHilOnlyWithoutOfficialPlistDoesNotLeaveNewOfficialPlist() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        let exactTree: Set<String> = ["old-binary"]
        host.trees[layout.applicationsAppPath] = exactTree
        host.loaded = [identity.hilLaunchdLabel]
        let hilPlist = Data("hil-only".utf8)
        host.files[layout.hilLaunchAgentPlistPath] = hilPlist
        XCTAssertNil(host.files[layout.launchAgentPlistPath])
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout,
            injectFailureAt: .writeLaunchAgent
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], exactTree)
        XCTAssertNil(host.files[layout.launchAgentPlistPath])
        XCTAssertEqual(host.files[layout.hilLaunchAgentPlistPath], hilPlist)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.hilLaunchdLabel])
    }

    func testOfficialOnlyAndDualOwnerPlistSnapshotsRestore() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old"]
        host.loaded = [identity.agentLaunchdLabel]
        host.files[layout.launchAgentPlistPath] = Data("official-only".utf8)
        var outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout,
            injectFailureAt: .registerLoginItem
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], Data("official-only".utf8))
        XCTAssertNil(host.files[layout.hilLaunchAgentPlistPath])
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])

        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.files[layout.launchAgentPlistPath] = Data("official-dual".utf8)
        host.files[layout.hilLaunchAgentPlistPath] = Data("hil-dual".utf8)
        host.trees[layout.applicationsAppPath] = ["old"]
        host.loginItemRegistered = false
        outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout,
            injectFailureAt: .bootstrap(label: identity.agentLaunchdLabel)
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertEqual(host.files[layout.launchAgentPlistPath], Data("official-dual".utf8))
        XCTAssertEqual(host.files[layout.hilLaunchAgentPlistPath], Data("hil-dual".utf8))
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel, identity.hilLaunchdLabel])
    }

    func testHostFalseSuccessWithoutPlistIsRejected() throws {
        let host = preparedHost()
        host.ignoreWrites = true
        let layout = self.layout(root: "/sandbox")
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .install(candidateAppPath: candidatePath()),
                host: host,
                layout: layout
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .terminalStateMismatch("official plist mismatch after install")
            )
        }
        XCTAssertNil(host.files[layout.launchAgentPlistPath])
        XCTAssertNil(host.trees[layout.applicationsAppPath])
    }

    func testRestoreReplacementRequiresPathGuard() throws {
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateReplacement(
                source: "/outside/backup.app",
                destination: "/sandbox/Applications/AhaKey Studio.app",
                backup: "/sandbox/Applications/AhaKey Studio.app.ahakey-rollback-scratch",
                staging: "/sandbox/Applications/AhaKey Studio.app.ahakey-staging",
                allowedRoots: ["/sandbox/Applications"],
                candidateRoots: ["/sandbox/Candidates"],
                sourceIsCandidate: false,
                permitsApplicationsDestination: false,
                itemExists: { _ in false },
                resolve: { $0 },
                isSymlink: { _ in false }
            )
        ) { error in
            guard case .pathEscapesAllowedRoot = error as? AhaKeyReleasePathViolation else {
                return XCTFail("\(error)")
            }
        }
    }

    func testTrustedRootsAreOnlyProducedByFactories() {
        let sandbox = AhaKeyReleaseInstallLayout.sandboxed(root: "/sandbox")
        XCTAssertEqual(
            Set(sandbox.trustedRoots),
            [
                "/sandbox/Applications",
                "/sandbox/LaunchAgents",
                "/sandbox/Home/Library/Application Support/AhaKeyConfig",
                "/sandbox/Home/Library/Application Support",
            ]
        )
        XCTAssertFalse(sandbox.trustedRoots.contains("/tmp"))
        XCTAssertFalse(sandbox.trustedRoots.contains("/"))
        var mutated = sandbox
        mutated.backupAppPath = "/tmp/forged-backup"
        mutated.applicationsAppPath = "/tmp/forged.app"
        mutated.stagingAppPath = "/tmp/forged-staging"
        mutated.rollbackScratchAppPath = "/tmp/forged-scratch"
        mutated.launchAgentPlistPath = "/tmp/forged.plist"
        XCTAssertEqual(mutated.trustedRoots, sandbox.trustedRoots)

        let production = AhaKeyReleaseInstallLayout.production()
        XCTAssertTrue(production.trustedRoots.contains("/Applications"))
        XCTAssertFalse(production.trustedRoots.contains("/tmp"))
        XCTAssertFalse(production.trustedRoots.contains("/"))
        // Structural proof: product-facing API only exposes `.production()`.
        // `.sandboxed` is internal/test-only (`@testable`); raw init is private
        // and cannot take caller-supplied trustedRoots (trustedRoots = ["/tmp"] is not expressible).
        let productFactory: () -> AhaKeyReleaseInstallLayout = { .production() }
        XCTAssertTrue(productFactory().permitsSystemApplicationsInstall)
        XCTAssertFalse(sandbox.permitsSystemApplicationsInstall)
    }

    func testMaliciousLayoutPathsAreRejectedWithZeroMutation() throws {
        struct Case {
            var name: String
            var mutate: (inout AhaKeyReleaseInstallLayout) -> Void
        }
        let cases: [Case] = [
            .init(name: "app") { $0.applicationsAppPath = "/tmp/ahakey-evil.app" },
            .init(name: "backup") { $0.backupAppPath = "/tmp/ahakey-evil-backup" },
            .init(name: "staging") { $0.stagingAppPath = "/tmp/ahakey-evil-staging" },
            .init(name: "scratch") { $0.rollbackScratchAppPath = "/tmp/ahakey-evil-scratch" },
            .init(name: "plist") { $0.launchAgentPlistPath = "/tmp/ahakey-evil.plist" },
        ]
        for item in cases {
            let host = preparedHost()
            var layout = self.layout(root: "/sandbox")
            host.trees[layout.applicationsAppPath] = ["do-not-touch"]
            host.loaded = [identity.agentLaunchdLabel]
            host.files[layout.launchAgentPlistPath] = Data("official".utf8)
            let exactTree = host.trees[layout.applicationsAppPath]
            let exactLoaded = host.loaded
            let exactPlist = host.files[layout.launchAgentPlistPath]
            item.mutate(&layout)
            XCTAssertThrowsError(
                try AhaKeyReleaseInstaller.run(
                    request: .upgrade(candidateAppPath: candidatePath()),
                    host: host,
                    layout: layout
                ),
                item.name
            ) { error in
                guard case .pathViolation(.pathEscapesAllowedRoot) = error as? AhaKeyReleaseInstallError else {
                    return XCTFail("\(item.name): \(error)")
                }
            }
            XCTAssertEqual(host.trees["/sandbox/Applications/AhaKey Studio.app"], exactTree, item.name)
            XCTAssertEqual(host.loaded, exactLoaded, item.name)
            XCTAssertEqual(
                host.files["/sandbox/LaunchAgents/\(identity.agentLaunchdLabel).plist"],
                exactPlist,
                item.name
            )
            XCTAssertTrue(host.writes.isEmpty, item.name)
        }
    }

    func testPlanEnablesOfficialBeforeBootstrapAndSkipsBackupRemovalWhenNonRestorable() throws {
        let layout = layout(root: "/sandbox")
        let snapshot = AhaKeyReleaseHostSnapshot(
            darwinMajor: 22,
            appInstalled: true,
            loadedLaunchdLabels: [identity.hilLaunchdLabel],
            previousAppIntegrity: .nonRestorable,
            disabledOverrides: AhaKeyReleaseDisabledOverrideSnapshot(officialDisabled: true)
        )
        let planned = AhaKeyReleaseInstallPlanner.plan(
            request: .upgrade(candidateAppPath: candidatePath()),
            snapshot: snapshot,
            layout: layout,
            candidate: try validCandidate(),
            previousOwnerRecords: [
                AhaKeyReleaseOwnerRecord(
                    label: identity.hilLaunchdLabel,
                    plistPath: layout.hilLaunchAgentPlistPath,
                    plist: Data("hil".utf8)
                )
            ]
        )
        guard case .success(let plan) = planned else {
            return XCTFail("nonRestorable 有效候选必须能计划，got \(planned)")
        }
        XCTAssertEqual(plan.previousAppIntegrity, .nonRestorable)
        XCTAssertTrue(plan.previousDisabledOverrides.officialDisabled)
        let enableIndex = plan.steps.firstIndex(of: .enable(label: identity.agentLaunchdLabel))
        let bootstrapIndex = plan.steps.firstIndex(of: .bootstrap(label: identity.agentLaunchdLabel))
        XCTAssertEqual(enableIndex, 3)
        XCTAssertEqual(bootstrapIndex, 4)
        XCTAssertFalse(plan.steps.contains(.removeBackup))
    }

    func testNonRestorableDisabledOfficialSucceedsWithoutRestoringBrokenBackup() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-broken"]
        host.installedAppIntegrity = .nonRestorable
        host.loaded = [identity.hilLaunchdLabel]
        host.disabled = [identity.agentLaunchdLabel]
        host.rejectReplaceFromBackup = true
        host.files[layout.launchAgentPlistPath] = Data("old-official".utf8)
        host.files[layout.hilLaunchAgentPlistPath] = Data("hil-plist".utf8)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout
        )
        XCTAssertFalse(outcome.rolledBack)
        XCTAssertFalse(outcome.failForwardPartial)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertTrue(outcome.loginItemRegistered)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["new-binary"])
        XCTAssertEqual(host.trees[layout.backupAppPath], ["old-broken"])
        XCTAssertFalse(host.disabled.contains(identity.agentLaunchdLabel))
        XCTAssertTrue(host.completedEnableBeforeBootstrap)
    }

    func testNonRestorableBootstrapFailureFailForwardsKeepingCandidateAndForensicBackup() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-broken"]
        host.installedAppIntegrity = .nonRestorable
        host.loaded = [identity.hilLaunchdLabel]
        host.disabled = [identity.agentLaunchdLabel]
        host.rejectReplaceFromBackup = true
        host.failingBootstrapLabels = [identity.agentLaunchdLabel]
        host.files[layout.launchAgentPlistPath] = Data("old-official".utf8)
        host.files[layout.hilLaunchAgentPlistPath] = Data("hil-plist".utf8)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout
        )
        XCTAssertTrue(outcome.failForwardPartial)
        XCTAssertFalse(outcome.rolledBack)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["new-binary"])
        XCTAssertEqual(host.trees[layout.backupAppPath], ["old-broken"])
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.hilLaunchdLabel])
        XCTAssertTrue(host.disabled.contains(identity.agentLaunchdLabel))
        XCTAssertEqual(host.files[layout.hilLaunchAgentPlistPath], Data("hil-plist".utf8))
        XCTAssertFalse(outcome.loginItemRegistered)
        XCTAssertTrue(host.bootstrapFailureOutput.contains("exit 5"))
    }

    func testNonRestorableCompensationWithoutUniqueOwnerIsBlockedWithBothErrors() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-broken"]
        host.installedAppIntegrity = .nonRestorable
        host.loaded = [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        host.rejectReplaceFromBackup = true
        host.files[layout.launchAgentPlistPath] = Data("old-official".utf8)
        host.files[layout.hilLaunchAgentPlistPath] = Data("hil-plist".utf8)
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: candidatePath()),
                host: host,
                layout: layout,
                injectFailureAt: .registerLoginItem
            )
        ) { error in
            guard case .blocked(let original, let compensation, let steps, let mutated, let snap, let reason) =
                error as? AhaKeyReleaseInstallError
            else {
                return XCTFail("无单 owner 必须 blocked，got \(error)")
            }
            XCTAssertEqual(original, .injectedFailure(.registerLoginItem))
            XCTAssertNotNil(compensation)
            XCTAssertTrue(steps.contains(.installApp))
            XCTAssertTrue(mutated)
            XCTAssertTrue(snap.appInstalled)
            XCTAssertTrue(reason.contains("unique owner"))
            XCTAssertEqual(host.trees[layout.applicationsAppPath], ["new-binary"])
            XCTAssertEqual(host.trees[layout.backupAppPath], ["old-broken"])
        }
    }

    func testEnableFailureKeepsLaunchctlOutput() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-binary"]
        host.installedAppIntegrity = .verifiedRestorable
        host.loaded = [identity.agentLaunchdLabel]
        host.files[layout.launchAgentPlistPath] = Data("previous".utf8)
        host.enableError = .hostFailure(
            "launchctl enable gui/501/\(identity.agentLaunchdLabel) exit 9: Could not enable service"
        )
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: candidatePath()),
                host: host,
                layout: layout
            )
        ) { error in
            let original: AhaKeyReleaseInstallError
            if case .compensationFailed(let inner, _, _, _, _) = error as? AhaKeyReleaseInstallError {
                original = inner
            } else if let install = error as? AhaKeyReleaseInstallError {
                original = install
            } else {
                return XCTFail("enable 失败必须可读，got \(error)")
            }
            guard case .hostFailure(let message) = original else {
                return XCTFail("enable 失败必须是 hostFailure，got \(original)")
            }
            XCTAssertTrue(message.contains("launchctl enable"), message)
            XCTAssertTrue(message.contains("exit 9"), message)
            XCTAssertTrue(message.contains("Could not enable service"), message)
            XCTAssertEqual(host.trees[layout.applicationsAppPath], ["old-binary"])
        }
    }

    func testVerifiedRestorableInjectedFailureStillExactRollsBack() throws {
        let host = preparedHost()
        let layout = self.layout(root: "/sandbox")
        host.trees[layout.applicationsAppPath] = ["old-binary"]
        host.installedAppIntegrity = .verifiedRestorable
        host.loaded = [identity.agentLaunchdLabel]
        host.files[layout.launchAgentPlistPath] = Data("previous-agent-plist".utf8)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: candidatePath()),
            host: host,
            layout: layout,
            injectFailureAt: .writeLaunchAgent
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertFalse(outcome.failForwardPartial)
        XCTAssertEqual(host.trees[layout.applicationsAppPath], ["old-binary"])
        XCTAssertNil(host.trees[layout.backupAppPath])
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
    }

    private func layout(root: String) -> AhaKeyReleaseInstallLayout {
        .sandboxed(root: root, identity: identity)
    }

    private func preparedHost() -> FakeInstallHost {
        let host = FakeInstallHost()
        host.darwinMajor = 22
        host.candidateReport = try? validCandidate()
        host.trees[candidatePath()] = ["new-binary"]
        return host
    }

    private func candidatePath(root: String = "/sandbox") -> String {
        (root as NSString).appendingPathComponent("Candidates/candidate.app")
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
            launchAgentPlist: plist,
            signingIdentifier: identity.signingIdentifier,
            signatureKind: .adhoc,
            appIntegrityVerified: true,
            agentIntegrityVerified: true,
            agentSigningIdentifier: identity.signingIdentifier,
            agentSignatureKind: .adhoc
        )
    }

    private func packagingIdentityURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packaging/ReleaseIdentity.json")
    }
}

private final class FakeInstallHost: AhaKeyReleaseInstallHost {
    var darwinMajor = 22
    var loaded: Set<String> = []
    var loginItemRegistered = false
    var files: [String: Data] = [:]
    var trees: [String: Set<String>] = [:]
    var preserved: [String: String] = [:]
    var writes: [String] = []
    var candidateReport: AhaKeyReleaseCandidateReport?
    var failReplaceAfterSuccesses = Int.max
    var replaceSuccesses = 0
    var failAfterCommittedReplace = false
    var failAfterCommittedMove = false
    var ignoreWrites = false
    var symlinks: [String: String] = [:]
    var installedAppIntegrity: AhaKeyReleasePreviousAppIntegrity = .verifiedRestorable
    var disabled: Set<String> = []
    var enableError: AhaKeyReleaseInstallError?
    var failingBootstrapLabels: Set<String> = []
    var rejectReplaceFromBackup = false
    var enableCalls: [String] = []
    var bootstrapCalls: [String] = []
    var bootstrapFailureOutput = ""
    var completedEnableBeforeBootstrap = false

    func snapshot(layout: AhaKeyReleaseInstallLayout) throws -> AhaKeyReleaseHostSnapshot {
        var exists: [String: Bool] = [:]
        for path in layout.preservedPaths {
            exists[path] = preserved[path] != nil
        }
        let identity = AhaKeyReleaseIdentity.current
        return AhaKeyReleaseHostSnapshot(
            darwinMajor: darwinMajor,
            appInstalled: itemExists(at: layout.applicationsAppPath),
            loadedLaunchdLabels: loaded,
            loginItemRegistered: loginItemRegistered,
            preservedPathExists: exists,
            previousAppIntegrity: itemExists(at: layout.applicationsAppPath) ? installedAppIntegrity : .missing,
            disabledOverrides: AhaKeyReleaseDisabledOverrideSnapshot(
                officialDisabled: disabled.contains(identity.agentLaunchdLabel),
                hilDisabled: disabled.contains(identity.hilLaunchdLabel)
            )
        )
    }

    func inspectCandidate(at appPath: String, identity: AhaKeyReleaseIdentity) throws -> AhaKeyReleaseCandidateReport {
        _ = appPath
        _ = identity
        guard let candidateReport else {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.candidateNotInspected))
        }
        return candidateReport
    }

    func itemExists(at path: String) -> Bool {
        trees[path] != nil || files[path] != nil
    }

    func isSymlink(_ path: String) -> Bool {
        symlinks[path] != nil
    }

    func resolvedPath(_ path: String) -> String? {
        symlinks[path] ?? path
    }

    func replaceDirectoryAtomically(from: String, to: String, backup: String, staging: String) throws {
        if rejectReplaceFromBackup, from.hasSuffix(".ahakey-backup") {
            throw AhaKeyReleaseInstallError.rejected(.identityRejected(.appIntegrityFailed))
        }
        if replaceSuccesses >= failReplaceAfterSuccesses {
            throw AhaKeyReleaseInstallError.hostFailure("injected replace failure")
        }
        replaceSuccesses += 1
        if from == to {
            throw AhaKeyReleaseInstallError.pathViolation(.sourceEqualsDestination)
        }
        if trees[backup] != nil {
            throw AhaKeyReleaseInstallError.pathViolation(.backupAlreadyExists(backup))
        }
        if trees[staging] != nil {
            throw AhaKeyReleaseInstallError.pathViolation(.stagingAlreadyExists(staging))
        }
        guard let incoming = trees[from] else {
            throw AhaKeyReleaseInstallError.hostFailure("missing source tree")
        }
        if let existing = trees[to] {
            trees[backup] = existing
        }
        trees[to] = incoming
        trees[staging] = nil
        try AhaKeyReleaseMutationBoundary.afterCommit {
            if failAfterCommittedReplace {
                failAfterCommittedReplace = false
                throw AhaKeyReleaseInstallError.hostFailure("injected fsync")
            }
        }
    }

    func moveDirectoryAtomically(from: String, to: String) throws {
        if trees[to] != nil {
            throw AhaKeyReleaseInstallError.pathViolation(.backupAlreadyExists(to))
        }
        guard let incoming = trees[from] else {
            throw AhaKeyReleaseInstallError.hostFailure("missing source tree")
        }
        trees[to] = incoming
        trees[from] = nil
        try AhaKeyReleaseMutationBoundary.afterCommit {
            if failAfterCommittedMove {
                failAfterCommittedMove = false
                throw AhaKeyReleaseInstallError.hostFailure("injected fsync")
            }
        }
    }

    func removeTree(_ path: String) throws {
        trees[path] = nil
        files[path] = nil
    }

    func writeFile(at path: String, data: Data) throws {
        writes.append(path)
        if ignoreWrites { return }
        files[path] = data
    }

    func readFile(at path: String) -> Data? {
        files[path]
    }

    func bootout(label: String) throws {
        loaded.remove(label)
    }

    func bootstrap(label: String, plistPath: String) throws {
        bootstrapCalls.append(label)
        if enableCalls.contains(AhaKeyReleaseIdentity.current.agentLaunchdLabel),
           label == AhaKeyReleaseIdentity.current.agentLaunchdLabel {
            completedEnableBeforeBootstrap = true
        }
        if failingBootstrapLabels.contains(label) {
            bootstrapFailureOutput =
                "launchctl bootstrap gui/501 \(plistPath) exit 5: Bootstrap failed: 5: Input/output error"
            throw AhaKeyReleaseInstallError.hostFailure(bootstrapFailureOutput)
        }
        if disabled.contains(label) {
            bootstrapFailureOutput =
                "launchctl bootstrap gui/501 \(plistPath) exit 5: Bootstrap failed: service is disabled"
            throw AhaKeyReleaseInstallError.hostFailure(bootstrapFailureOutput)
        }
        loaded.insert(label)
    }

    func registerLoginItem() throws {
        loginItemRegistered = true
    }

    func unregisterLoginItem() throws {
        loginItemRegistered = false
    }

    func disabledLaunchdLabels() throws -> Set<String> { disabled }

    func setLaunchdDisabled(label: String, disabled: Bool) throws {
        if !disabled {
            enableCalls.append(label)
        }
        if let enableError, !disabled {
            throw enableError
        }
        if disabled {
            self.disabled.insert(label)
        } else {
            self.disabled.remove(label)
        }
    }
}
