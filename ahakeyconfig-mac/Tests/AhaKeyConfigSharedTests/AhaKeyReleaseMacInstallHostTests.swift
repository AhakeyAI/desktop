import Darwin
import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyReleaseMacInstallHostTests: XCTestCase {
    private let identity = AhaKeyReleaseIdentity.current

    func testMacHostAtomicReplaceDropsStaleFiles() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        let installed = try makeAppFixture(in: root, name: "installed.app", marker: "stale-extra")
        try FileManager.default.moveItem(atPath: installed.app, toPath: layout.applicationsAppPath)
        let staleDir = (layout.applicationsAppPath as NSString).appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(atPath: staleDir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: (staleDir as NSString).appendingPathComponent("stale-extra"),
            contents: Data("old".utf8)
        )

        let candidate = try makeAppFixture(in: root, name: "candidate.app", marker: "new-binary")
        let system = AhaKeyReleaseRecordingSystemControl(useProcessCodesign: true)
        system.signatures = [:]
        let host = AhaKeyReleaseMacInstallHost(system: system)
        try host.replaceDirectoryAtomically(
            from: candidate.app,
            to: layout.applicationsAppPath,
            backup: layout.backupAppPath,
            staging: layout.stagingAppPath
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: (layout.applicationsAppPath as NSString).appendingPathComponent("Contents/Resources/stale-extra")
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: identity.agentBinaryPath(inApp: layout.applicationsAppPath)
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.backupAppPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.stagingAppPath))
    }

    func testMacHostInspectsAdHocCandidateAndRejectsDeveloperIDClaim() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fixture = try makeAppFixture(in: root, name: "AhaKey Studio.app", marker: "agent")
        let system = AhaKeyReleaseRecordingSystemControl(useProcessCodesign: true)
        let host = AhaKeyReleaseMacInstallHost(system: system)
        let report = try host.inspectCandidate(at: fixture.app, identity: identity)
        XCTAssertEqual(AhaKeyReleaseSigningChecklist.check(report), .unsignedCandidateReady)
        XCTAssertEqual(report.signatureKind, .adhoc)
        XCTAssertEqual(report.signingIdentifier, identity.signingIdentifier)
        XCTAssertNil(report.teamIdentifier)
        XCTAssertTrue(report.appIntegrityVerified)
        XCTAssertTrue(report.agentIntegrityVerified)
        XCTAssertEqual(report.agentSigningIdentifier, identity.signingIdentifier)
        XCTAssertEqual(report.agentSignatureKind, .adhoc)
        XCTAssertNil(report.agentTeamIdentifier)
    }

    func testMacHostEndToEndSandboxInstall() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        try FileManager.default.createDirectory(atPath: layout.launchAgentsDirectory, withIntermediateDirectories: true)
        let candidates = (root as NSString).appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(atPath: candidates, withIntermediateDirectories: true)
        let fixture = try makeAppFixture(in: candidates, name: "AhaKey Studio.app", marker: "agent")
        let system = AhaKeyReleaseRecordingSystemControl(darwinMajorValue: 22, useProcessCodesign: true)
        let host = AhaKeyReleaseMacInstallHost(system: system)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .install(candidateAppPath: fixture.app),
            host: host,
            layout: layout
        )
        XCTAssertFalse(outcome.rolledBack)
        XCTAssertTrue(outcome.appInstalled)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.applicationsAppPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.backupAppPath))
        XCTAssertEqual(outcome.snapshot.previousAppIntegrity, .verifiedRestorable)
        XCTAssertFalse(outcome.snapshot.installedAppFingerprint.isEmpty)
        XCTAssertTrue(outcome.mutationReceipt.appWasMutated)
        XCTAssertTrue(outcome.mutationReceipt.completedSteps.contains(.installApp))
    }

    func testLaunchdControlRefusesSystemMutationByDefault() {
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: false)
        XCTAssertThrowsError(try control.bootout(label: identity.agentLaunchdLabel)) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.systemMutationNotAllowed)
            )
        }
        XCTAssertThrowsError(try control.registerLoginItem())
        XCTAssertThrowsError(try control.setLaunchdDisabled(label: identity.agentLaunchdLabel, disabled: false)) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.systemMutationNotAllowed)
            )
        }
    }

    func testLaunchdControlPrintDisabledAndEnableKeepCommandStatusOutput() throws {
        let process = AhaKeyReleaseRecordingProcessRunner()
        let uid = getuid()
        process.outputByJoinedArguments["print-disabled gui/\(uid)"] = """
        disabled = {
                "com.apple.Safari" => disabled
                "\(identity.agentLaunchdLabel)" => disabled
                "\(identity.hilLaunchdLabel)" => enabled
        }
        """
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: true, process: process)
        XCTAssertEqual(
            try control.disabledLaunchdLabels(),
            ["com.apple.Safari", identity.agentLaunchdLabel]
        )

        process.statusByJoinedArguments["print-disabled gui/\(uid)"] = 4
        process.outputByJoinedArguments["print-disabled gui/\(uid)"] = "print-disabled denied"
        XCTAssertThrowsError(try control.disabledLaunchdLabels()) { error in
            guard case .hostFailure(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("print-disabled 非零必须保留 command/status/output，got \(error)")
            }
            XCTAssertTrue(message.contains("launchctl print-disabled"), message)
            XCTAssertTrue(message.contains("exit 4"), message)
            XCTAssertTrue(message.contains("print-disabled denied"), message)
        }

        process.statusByJoinedArguments["enable gui/\(uid)/\(identity.agentLaunchdLabel)"] = 9
        process.outputByJoinedArguments["enable gui/\(uid)/\(identity.agentLaunchdLabel)"] =
            "Could not enable service"
        XCTAssertThrowsError(
            try control.setLaunchdDisabled(label: identity.agentLaunchdLabel, disabled: false)
        ) { error in
            guard case .hostFailure(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("enable 非零必须保留 command/status/output，got \(error)")
            }
            XCTAssertTrue(message.contains("launchctl enable"), message)
            XCTAssertTrue(message.contains("exit 9"), message)
            XCTAssertTrue(message.contains("Could not enable service"), message)
        }
    }

    func testMacHostSnapshotClassifiesBrokenPreviousAppAsNonRestorable() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        let previous = try makeAppFixture(in: root, name: "AhaKey Studio.app", marker: "old")
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(atPath: previous.app, toPath: layout.applicationsAppPath)
        try tamperAppSeal(layout.applicationsAppPath)
        let system = AhaKeyReleaseRecordingSystemControl(useProcessCodesign: true)
        system.disabled = [identity.agentLaunchdLabel]
        system.loaded = [identity.hilLaunchdLabel]
        let host = AhaKeyReleaseMacInstallHost(system: system)
        let snapshot = try host.snapshot(layout: layout)
        XCTAssertEqual(snapshot.previousAppIntegrity, .nonRestorable)
        XCTAssertTrue(snapshot.disabledOverrides.officialDisabled)
        XCTAssertEqual(snapshot.loadedLaunchdLabels, [identity.hilLaunchdLabel])
    }

    func testMacHostSnapshotUsesInjectedIdentityForAgentPathAndDisabledLabels() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let current = identity
        let custom = AhaKeyReleaseIdentity(
            channel: current.channel,
            productVersion: current.productVersion,
            bundleIdentifier: current.bundleIdentifier,
            signingIdentifier: current.signingIdentifier,
            teamIdentifier: current.teamIdentifier,
            appDisplayName: current.appDisplayName,
            appBundleFileName: current.appBundleFileName,
            executableName: current.executableName,
            agentBinaryName: "custom-agent",
            agentLaunchdLabel: "lab.test.custom.agent",
            hilLaunchdLabel: "lab.test.custom.agent.hil",
            machServiceName: current.machServiceName,
            minimumDarwinMajor: current.minimumDarwinMajor,
            minimumMacOSVersion: current.minimumMacOSVersion
        )
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root, identity: custom)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let fixture = try makeAppFixture(in: root, name: "AhaKey Studio.app", marker: "custom", identity: custom)
        try FileManager.default.copyItem(atPath: fixture.app, toPath: layout.applicationsAppPath)
        let customSystem = AhaKeyReleaseRecordingSystemControl(identity: custom, useProcessCodesign: true)
        customSystem.disabled = [custom.agentLaunchdLabel, custom.hilLaunchdLabel]
        let customHost = AhaKeyReleaseMacInstallHost(system: customSystem)
        let customSnap = try customHost.snapshot(layout: layout)
        XCTAssertEqual(customHost.identity, custom)
        XCTAssertEqual(customSnap.previousAppIntegrity, .verifiedRestorable)
        XCTAssertTrue(customSnap.disabledOverrides.officialDisabled)
        XCTAssertTrue(customSnap.disabledOverrides.hilDisabled)

        let defaultSystem = AhaKeyReleaseRecordingSystemControl(useProcessCodesign: true)
        defaultSystem.disabled = [custom.agentLaunchdLabel, custom.hilLaunchdLabel]
        let defaultHost = AhaKeyReleaseMacInstallHost(system: defaultSystem)
        let defaultSnap = try defaultHost.snapshot(layout: layout)
        XCTAssertEqual(defaultHost.identity, .current)
        XCTAssertEqual(defaultSnap.previousAppIntegrity, .nonRestorable)
        XCTAssertFalse(defaultSnap.disabledOverrides.officialDisabled)
        XCTAssertFalse(defaultSnap.disabledOverrides.hilDisabled)
    }

    func testMacHostCustomIdentityInstallerRollsBackHilPlistAndOwner() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let custom = customTestIdentity()
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root, identity: custom)
        XCTAssertTrue(layout.hilLaunchAgentPlistPath.hasSuffix("\(custom.hilLaunchdLabel).plist"))
        XCTAssertNotEqual(
            layout.hilLaunchAgentPlistPath,
            AhaKeyReleaseInstallLayout.sandboxed(root: root).hilLaunchAgentPlistPath
        )
        try FileManager.default.createDirectory(atPath: layout.launchAgentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let previous = try makeAppFixture(in: root, name: "previous.app", marker: "old", identity: custom)
        try FileManager.default.copyItem(atPath: previous.app, toPath: layout.applicationsAppPath)
        try Data("custom-hil".utf8).write(to: URL(fileURLWithPath: layout.hilLaunchAgentPlistPath))
        let candidates = (root as NSString).appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(atPath: candidates, withIntermediateDirectories: true)
        let fixture = try makeAppFixture(in: candidates, name: "AhaKey Studio.app", marker: "new", identity: custom)
        let system = AhaKeyReleaseRecordingSystemControl(
            identity: custom,
            darwinMajorValue: 22,
            useProcessCodesign: true
        )
        system.loaded = [custom.hilLaunchdLabel]
        system.disabled = [custom.agentLaunchdLabel]
        let host = AhaKeyReleaseMacInstallHost(system: system)
        XCTAssertEqual(host.identity, custom)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: fixture.app),
            host: host,
            layout: layout,
            identity: custom,
            injectFailureAt: .writeLaunchAgent
        )
        XCTAssertTrue(outcome.rolledBack)
        XCTAssertFalse(outcome.failForwardPartial)
        XCTAssertEqual(outcome.snapshot.loadedLaunchdLabels, [custom.hilLaunchdLabel])
        XCTAssertTrue(outcome.snapshot.disabledOverrides.officialDisabled)
        XCTAssertFalse(outcome.snapshot.disabledOverrides.hilDisabled)
        XCTAssertEqual(outcome.snapshot.previousAppIntegrity, .verifiedRestorable)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: layout.hilLaunchAgentPlistPath)),
            Data("custom-hil".utf8)
        )
        XCTAssertTrue(outcome.mutationReceipt.appWasMutated)
        XCTAssertEqual(system.loaded, [custom.hilLaunchdLabel])
        XCTAssertTrue(system.disabled.contains(custom.agentLaunchdLabel))
    }

    func testMacHostIdentityMismatchFailsClosedWithoutReplacingApp() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let custom = customTestIdentity()
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root, identity: custom)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let previous = try makeAppFixture(in: root, name: "previous.app", marker: "old")
        try FileManager.default.copyItem(atPath: previous.app, toPath: layout.applicationsAppPath)
        let candidates = (root as NSString).appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(atPath: candidates, withIntermediateDirectories: true)
        let fixture = try makeAppFixture(in: candidates, name: "AhaKey Studio.app", marker: "new")
        let system = AhaKeyReleaseRecordingSystemControl(darwinMajorValue: 22, useProcessCodesign: true)
        let host = AhaKeyReleaseMacInstallHost(system: system)
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: fixture.app),
                host: host,
                layout: layout,
                identity: custom
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.identityContextMismatch)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.applicationsAppPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.backupAppPath))
        XCTAssertTrue(system.loaded.isEmpty)
    }

    func testMacHostInitRejectsSystemIdentityMismatch() {
        let custom = customTestIdentity()
        let system = AhaKeyReleaseRecordingSystemControl()
        XCTAssertEqual(system.identity, .current)
        XCTAssertThrowsError(
            try AhaKeyReleaseMacInstallHost(system: system, identity: custom)
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.identityContextMismatch)
            )
        }
    }

    func testLaunchdControlCustomIdentityQueriesCustomLabels() throws {
        let custom = customTestIdentity()
        let process = AhaKeyReleaseRecordingProcessRunner()
        let uid = getuid()
        process.outputByJoinedArguments["list"] = """
        PID\tStatus\tLabel
        -\t0\t\(custom.agentLaunchdLabel)
        """
        process.statusByJoinedArguments["print gui/\(uid)/\(custom.agentLaunchdLabel)"] = 0
        process.statusByJoinedArguments["print gui/\(uid)/\(custom.hilLaunchdLabel)"] = 113
        process.outputByJoinedArguments["print gui/\(uid)/\(custom.hilLaunchdLabel)"] =
            "Could not find service \"\(custom.hilLaunchdLabel)\" in domain for id \(uid)"
        let control = AhaKeyReleaseLaunchdControl(
            allowSystemMutation: false,
            process: process,
            identity: custom
        )
        XCTAssertEqual(control.identity, custom)
        XCTAssertEqual(try control.loadedLaunchdLabels(), [custom.agentLaunchdLabel])
        let joined = process.calls.map { $0.joined(separator: " ") }
        XCTAssertTrue(joined.contains { $0.contains(custom.agentLaunchdLabel) })
        XCTAssertTrue(joined.contains { $0.contains(custom.hilLaunchdLabel) })
        XCTAssertFalse(joined.contains { $0.contains(identity.agentLaunchdLabel) })
        XCTAssertFalse(joined.contains { $0.contains(identity.hilLaunchdLabel) })
    }

    func testMacHostTreeDigestDistinguishesSameExecutableNamesWithDifferentContent() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let oldApp = try makeAppFixture(in: root, name: "old.app", marker: "old-payload")
        let newApp = try makeAppFixture(in: root, name: "new.app", marker: "new-payload")
        XCTAssertEqual(try macosNames(in: oldApp.app), try macosNames(in: newApp.app))
        XCTAssertEqual(try macosNames(in: oldApp.app).sorted(), [identity.agentBinaryName, identity.executableName].sorted())
        let host = AhaKeyReleaseMacInstallHost(system: AhaKeyReleaseRecordingSystemControl(useProcessCodesign: true))
        let oldDigest = try host.appFingerprint(at: oldApp.app)
        let newDigest = try host.appFingerprint(at: newApp.app)
        XCTAssertNotEqual(oldDigest, newDigest)
        XCTAssertFalse(oldDigest.isEmpty)
        XCTAssertThrowsError(try host.appFingerprint(at: (root as NSString).appendingPathComponent("missing.app"))) { error in
            guard case .hostFailure(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("不可读树必须抛错，got \(error)")
            }
            XCTAssertTrue(message.contains("unreadable"), message)
        }

        let collideA = (root as NSString).appendingPathComponent("collide-a")
        let collideB = (root as NSString).appendingPathComponent("collide-b")
        try FileManager.default.createDirectory(atPath: collideA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: collideB, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: (collideA as NSString).appendingPathComponent("link"),
            withDestinationPath: "a"
        )
        try Data("x".utf8).write(to: URL(fileURLWithPath: (collideA as NSString).appendingPathComponent("bc")))
        try FileManager.default.createSymbolicLink(
            atPath: (collideB as NSString).appendingPathComponent("link"),
            withDestinationPath: "ab"
        )
        try Data("x".utf8).write(to: URL(fileURLWithPath: (collideB as NSString).appendingPathComponent("c")))
        XCTAssertNotEqual(try host.appFingerprint(at: collideA), try host.appFingerprint(at: collideB))
    }

    func testMacHostExactRollbackRejectsWrongTreeWithSameExecutableNames() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        try FileManager.default.createDirectory(atPath: layout.launchAgentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let previous = try makeAppFixture(in: root, name: "previous.app", marker: "old-payload")
        try FileManager.default.copyItem(atPath: previous.app, toPath: layout.applicationsAppPath)
        try Data("previous".utf8).write(to: URL(fileURLWithPath: layout.launchAgentPlistPath))
        let candidates = (root as NSString).appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(atPath: candidates, withIntermediateDirectories: true)
        let candidate = try makeAppFixture(in: candidates, name: "AhaKey Studio.app", marker: "new-payload")
        let wrong = try makeAppFixture(in: root, name: "wrong.app", marker: "wrong-payload")
        XCTAssertEqual(try macosNames(in: previous.app), try macosNames(in: wrong.app))
        let system = AhaKeyReleaseRecordingSystemControl(darwinMajorValue: 22, useProcessCodesign: true)
        system.loaded = [identity.agentLaunchdLabel]
        let inner = AhaKeyReleaseMacInstallHost(system: system)
        let host = TerminalTreeMutatingHost(inner: inner, wrongTreePath: wrong.app)
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: candidate.app),
                host: host,
                layout: layout,
                injectFailureAt: .writeLaunchAgent
            )
        ) { error in
            guard case .blocked(let original, let compensation, _, let mutated, let snap, let reason) =
                error as? AhaKeyReleaseInstallError
            else {
                return XCTFail("错树必须 blocked，got \(error)")
            }
            XCTAssertEqual(original, .injectedFailure(.writeLaunchAgent))
            XCTAssertNotNil(compensation)
            XCTAssertTrue(mutated)
            XCTAssertEqual(snap.installedAppFingerprint, try? inner.appFingerprint(at: layout.applicationsAppPath))
            XCTAssertEqual(try? inner.appFingerprint(at: layout.applicationsAppPath), try? inner.appFingerprint(at: wrong.app))
            XCTAssertTrue(reason.lowercased().contains("integrity") || reason.lowercased().contains("tree"), reason)
        }
    }

    func testMacHostFailForwardRejectsWrongTreeWithSameExecutableNames() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        try FileManager.default.createDirectory(atPath: layout.launchAgentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let previous = try makeAppFixture(in: root, name: "previous.app", marker: "old-broken")
        try FileManager.default.copyItem(atPath: previous.app, toPath: layout.applicationsAppPath)
        try tamperAppSeal(layout.applicationsAppPath)
        try Data("hil-plist".utf8).write(to: URL(fileURLWithPath: layout.hilLaunchAgentPlistPath))
        let candidates = (root as NSString).appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(atPath: candidates, withIntermediateDirectories: true)
        let candidate = try makeAppFixture(in: candidates, name: "AhaKey Studio.app", marker: "new-payload")
        let wrong = try makeAppFixture(in: root, name: "wrong.app", marker: "wrong-payload")
        XCTAssertEqual(try macosNames(in: candidate.app), try macosNames(in: wrong.app))
        let system = AhaKeyReleaseRecordingSystemControl(darwinMajorValue: 22, useProcessCodesign: true)
        system.loaded = [identity.hilLaunchdLabel]
        system.disabled = [identity.agentLaunchdLabel]
        system.failingVerifyIfPathContains = ".ahakey-backup"
        system.failingBootstrapLabels = [identity.agentLaunchdLabel]
        system.bootstrapError = .hostFailure(
            "launchctl bootstrap gui/501 \(layout.launchAgentPlistPath) exit 5: Bootstrap failed: 5: Input/output error"
        )
        let inner = AhaKeyReleaseMacInstallHost(system: system)
        let host = TerminalTreeMutatingHost(inner: inner, wrongTreePath: wrong.app)
        XCTAssertThrowsError(
            try AhaKeyReleaseInstaller.run(
                request: .upgrade(candidateAppPath: candidate.app),
                host: host,
                layout: layout
            )
        ) { error in
            guard case .blocked(let original, let compensation, _, let mutated, let snap, let reason) =
                error as? AhaKeyReleaseInstallError
            else {
                return XCTFail("fail-forward 错树必须 blocked，got \(error)")
            }
            guard case .hostFailure(let message) = original else {
                return XCTFail("必须保留 bootstrap 原错，got \(String(describing: original))")
            }
            XCTAssertTrue(message.contains("launchctl bootstrap"), message)
            XCTAssertNotNil(compensation)
            XCTAssertTrue(mutated)
            XCTAssertEqual(snap.installedAppFingerprint, try? inner.appFingerprint(at: layout.applicationsAppPath))
            XCTAssertEqual(try? inner.appFingerprint(at: layout.applicationsAppPath), try? inner.appFingerprint(at: wrong.app))
            XCTAssertTrue(
                reason.lowercased().contains("integrity")
                    || reason.lowercased().contains("tree")
                    || reason.lowercased().contains("verified"),
                reason
            )
        }
    }

    func testMacHostNonRestorableUpgradeEnablesOfficialAndKeepsForensicBackup() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        try FileManager.default.createDirectory(atPath: layout.launchAgentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let previous = try makeAppFixture(in: root, name: "previous.app", marker: "old")
        try FileManager.default.copyItem(atPath: previous.app, toPath: layout.applicationsAppPath)
        try tamperAppSeal(layout.applicationsAppPath)
        try Data("hil-plist".utf8).write(to: URL(fileURLWithPath: layout.hilLaunchAgentPlistPath))
        let candidates = (root as NSString).appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(atPath: candidates, withIntermediateDirectories: true)
        let fixture = try makeAppFixture(in: candidates, name: "AhaKey Studio.app", marker: "new")
        let system = AhaKeyReleaseRecordingSystemControl(darwinMajorValue: 22, useProcessCodesign: true)
        system.loaded = [identity.hilLaunchdLabel]
        system.disabled = [identity.agentLaunchdLabel]
        system.failingVerifyIfPathContains = ".ahakey-backup"
        let host = AhaKeyReleaseMacInstallHost(system: system)
        let outcome = try AhaKeyReleaseInstaller.run(
            request: .upgrade(candidateAppPath: fixture.app),
            host: host,
            layout: layout
        )
        XCTAssertFalse(outcome.rolledBack)
        XCTAssertFalse(outcome.failForwardPartial)
        XCTAssertEqual(outcome.loadedLaunchdLabels, [identity.agentLaunchdLabel])
        XCTAssertTrue(outcome.loginItemRegistered)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.applicationsAppPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.backupAppPath))
        XCTAssertFalse(system.disabled.contains(identity.agentLaunchdLabel))
        XCTAssertEqual(system.loaded, [identity.agentLaunchdLabel])
    }

    func testSymlinkOnDiskIsRejectedByPathGuard() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let outside = (root as NSString).appendingPathComponent("outside")
        let apps = (root as NSString).appendingPathComponent("Applications")
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: apps, withDestinationPath: outside)
        let dest = (apps as NSString).appendingPathComponent("AhaKey Studio.app")
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateReplacement(
                source: (root as NSString).appendingPathComponent("candidate.app"),
                destination: dest,
                backup: dest + ".ahakey-backup",
                staging: dest + ".ahakey-staging",
                allowedRoots: [apps],
                candidateRoots: [root],
                permitsApplicationsDestination: false,
                itemExists: FileManager.default.fileExists(atPath:),
                resolve: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                isSymlink: { path in
                    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                    return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
                }
            )
        )
    }

    func testLaunchdControlReadsListAndPrintAndThrowsOnNonZero() throws {
        let process = AhaKeyReleaseRecordingProcessRunner()
        let uid = getuid()
        process.outputByJoinedArguments["list"] = """
        PID\tStatus\tLabel
        -\t0\t\(identity.agentLaunchdLabel)
        -\t0\t\(identity.hilLaunchdLabel)
        """
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = 0
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] = 0
        let control = AhaKeyReleaseLaunchdControl(
            allowSystemMutation: true,
            process: process
        )
        XCTAssertEqual(
            try control.loadedLaunchdLabels(),
            [identity.agentLaunchdLabel, identity.hilLaunchdLabel]
        )

        process.statusByJoinedArguments["list"] = 1
        process.outputByJoinedArguments["list"] = "launchctl list failed"
        XCTAssertThrowsError(try control.loadedLaunchdLabels()) { error in
            guard case .hostFailure = error as? AhaKeyReleaseInstallError else {
                return XCTFail("list 非零必须抛 hostFailure，got \(error)")
            }
        }

        process.statusByJoinedArguments["list"] = 0
        process.statusByJoinedArguments["bootout gui/\(uid)/\(identity.agentLaunchdLabel)"] = 5
        XCTAssertThrowsError(try control.bootout(label: identity.agentLaunchdLabel)) { error in
            guard case .hostFailure = error as? AhaKeyReleaseInstallError else {
                return XCTFail("bootout 非零必须抛 hostFailure，got \(error)")
            }
        }

        process.statusByJoinedArguments["bootstrap gui/\(uid) /tmp/agent.plist"] = 7
        XCTAssertThrowsError(
            try control.bootstrap(label: identity.agentLaunchdLabel, plistPath: "/tmp/agent.plist")
        ) { error in
            guard case .hostFailure = error as? AhaKeyReleaseInstallError else {
                return XCTFail("bootstrap 非零必须抛 hostFailure，got \(error)")
            }
        }
    }

    func testLaunchdControlPrintDiscoversOfficialOwnerWhenListOmitsIt() throws {
        let process = AhaKeyReleaseRecordingProcessRunner()
        let uid = getuid()
        process.outputByJoinedArguments["list"] = """
        PID\tStatus\tLabel
        -\t0\tcom.apple.accountsd
        """
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = 0
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] = 113
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] =
            "Could not find service \"\(identity.hilLaunchdLabel)\" in domain for id \(uid)"
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: false, process: process)
        XCTAssertEqual(try control.loadedLaunchdLabels(), [identity.agentLaunchdLabel])
    }

    func testLaunchdControlPrintUnexpectedNonZeroIsNotSwallowed() throws {
        let process = AhaKeyReleaseRecordingProcessRunner()
        let uid = getuid()
        process.outputByJoinedArguments["list"] = """
        PID\tStatus\tLabel
        -\t0\tcom.apple.accountsd
        """
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = 1
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = "Permission denied"
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] = 113
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] =
            "Could not find service \"\(identity.hilLaunchdLabel)\" in domain for id \(uid)"
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: false, process: process)
        XCTAssertThrowsError(try control.loadedLaunchdLabels()) { error in
            guard case .hostFailure(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("unexpected print 非零必须传播，got \(error)")
            }
            XCTAssertTrue(message.contains("Permission denied"), message)
        }
    }

    func testProductionHostFactoryIsWiredAndRefusesMutation() {
        let host = AhaKeyReleaseInstaller.productionHost()
        _ = host
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: false)
        XCTAssertThrowsError(try control.bootout(label: identity.agentLaunchdLabel)) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.systemMutationNotAllowed)
            )
        }
    }

    func testPlistWriteOverwritesWithoutRemovingDestination() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = (root as NSString).appendingPathComponent("LaunchAgents/lab.jawa.ahakeyconfig.agent.plist")
        let host = AhaKeyReleaseMacInstallHost(system: AhaKeyReleaseRecordingSystemControl())
        try host.writeFile(at: path, data: Data("v1".utf8))
        XCTAssertEqual(host.readFile(at: path), Data("v1".utf8))
        try host.writeFile(at: path, data: Data("v2-longer-payload".utf8))
        XCTAssertEqual(host.readFile(at: path), Data("v2-longer-payload".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let temp = ((path as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(".lab.jawa.ahakeyconfig.agent.plist.ahakey-tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp))
    }

    func testPlistWriteRefusesDestinationSymlinkAndPreservesTarget() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let directory = (root as NSString).appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let outside = (root as NSString).appendingPathComponent("outside.plist")
        try Data("secret".utf8).write(to: URL(fileURLWithPath: outside))
        let dest = (directory as NSString).appendingPathComponent("lab.jawa.ahakeyconfig.agent.plist")
        try FileManager.default.createSymbolicLink(atPath: dest, withDestinationPath: outside)
        let host = AhaKeyReleaseMacInstallHost(system: AhaKeyReleaseRecordingSystemControl())
        XCTAssertThrowsError(try host.writeFile(at: dest, data: Data("owned".utf8))) { error in
            guard case .pathViolation(.pathContainsSymlink) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("\(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: outside)), Data("secret".utf8))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: dest),
            outside
        )
    }

    func testPlistWriteFailureBeforeRenameLeavesExistingPlist() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = (root as NSString).appendingPathComponent("LaunchAgents/lab.jawa.ahakeyconfig.agent.plist")
        let host = AhaKeyReleaseMacInstallHost(system: AhaKeyReleaseRecordingSystemControl())
        try host.writeFile(at: path, data: Data("keep-me".utf8))
        host.injectedWriteFailure = .afterFsync
        XCTAssertThrowsError(try host.writeFile(at: path, data: Data("new".utf8)))
        XCTAssertEqual(host.readFile(at: path), Data("keep-me".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: (path as NSString).deletingLastPathComponent
        ).filter { $0.hasPrefix(".ahakey-") && $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "失败后不得留下临时文件: \(leftovers)")
    }

    func testExclusiveCreateDoesNotFollowSymlink() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let outside = (root as NSString).appendingPathComponent("outside")
        try Data("secret".utf8).write(to: URL(fileURLWithPath: outside))
        let link = (root as NSString).appendingPathComponent(".ahakey-collision.tmp")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: outside)
        let fd = open(link, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        XCTAssertTrue(fd < 0, "预置 symlink 不得被独占打开")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: outside)), Data("secret".utf8))
    }

    func testReplaceFsyncFailureAfterCommitReportsMutation() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let installed = try makeAppFixture(in: root, name: "installed.app", marker: "old")
        try FileManager.default.moveItem(atPath: installed.app, toPath: layout.applicationsAppPath)
        let candidate = try makeAppFixture(in: root, name: "candidate.app", marker: "new")
        let system = AhaKeyReleaseRecordingSystemControl(useProcessCodesign: true)
        let host = AhaKeyReleaseMacInstallHost(system: system)
        host.injectedDirectoryFsyncError = .hostFailure("injected fsync")
        XCTAssertThrowsError(
            try host.replaceDirectoryAtomically(
                from: candidate.app,
                to: layout.applicationsAppPath,
                backup: layout.backupAppPath,
                staging: layout.stagingAppPath
            )
        ) { error in
            guard case .failedAfterAppMutation(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("真实 fsync hostFailure 必须转换为 mutation receipt，got \(error)")
            }
            XCTAssertTrue(message.contains("injected fsync"), message)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.applicationsAppPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.backupAppPath))
    }

    func testStagingReverifyRejectsTamperedAgentBeforeSwap() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = AhaKeyReleaseInstallLayout.sandboxed(root: root)
        try FileManager.default.createDirectory(
            atPath: (layout.applicationsAppPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let installed = try makeAppFixture(in: root, name: "installed.app", marker: "old")
        try FileManager.default.moveItem(atPath: installed.app, toPath: layout.applicationsAppPath)
        let candidate = try makeAppFixture(in: root, name: "candidate.app", marker: "new")
        let system = AhaKeyReleaseRecordingSystemControl(useProcessCodesign: true)
        system.failingVerifyIfPathContains = ".ahakey-staging"
        let host = AhaKeyReleaseMacInstallHost(system: system)
        XCTAssertThrowsError(
            try host.replaceDirectoryAtomically(
                from: candidate.app,
                to: layout.applicationsAppPath,
                backup: layout.backupAppPath,
                staging: layout.stagingAppPath
            )
        ) { error in
            XCTAssertEqual(
                error as? AhaKeyReleaseInstallError,
                .rejected(.identityRejected(.appIntegrityFailed))
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: identity.agentBinaryPath(inApp: layout.applicationsAppPath)
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.backupAppPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.stagingAppPath))
    }

    func testCandidateParentDirectorySymlinkIsRejectedOnDisk() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let real = (root as NSString).appendingPathComponent("real-candidates")
        let candidates = (root as NSString).appendingPathComponent("Candidates")
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: candidates, withDestinationPath: real)
        let source = (candidates as NSString).appendingPathComponent("candidate.app")
        XCTAssertThrowsError(
            try AhaKeyReleasePathGuard.validateCandidateSource(
                source,
                candidateRoots: [candidates],
                isSymlink: { path in
                    (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
                }
            )
        ) { error in
            guard case .pathContainsSymlink = error as? AhaKeyReleasePathViolation else {
                return XCTFail("\(error)")
            }
        }
    }

    func testLaunchdControlGenericNoSuchProcessIsNotTreatedAsNotFound() throws {
        let process = AhaKeyReleaseRecordingProcessRunner()
        let uid = getuid()
        process.outputByJoinedArguments["list"] = "PID\tStatus\tLabel\n"
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = 113
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = "no such process"
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] = 113
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] =
            "Could not find service \"\(identity.hilLaunchdLabel)\" in domain for id \(uid)"
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: false, process: process)
        XCTAssertThrowsError(try control.loadedLaunchdLabels()) { error in
            guard case .hostFailure(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("泛化 no such process 必须传播，got \(error)")
            }
            XCTAssertTrue(message.contains("no such process"), message)
        }
    }

    func testLaunchdControlWrongStatusOrDomainErrorIsPropagated() throws {
        let process = AhaKeyReleaseRecordingProcessRunner()
        let uid = getuid()
        process.outputByJoinedArguments["list"] = "PID\tStatus\tLabel\n"
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = 1
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] =
            "Could not find service \"\(identity.agentLaunchdLabel)\" in domain for id \(uid)"
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] = 113
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] =
            "Could not find service \"\(identity.hilLaunchdLabel)\" in domain for id \(uid)"
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: false, process: process)
        XCTAssertThrowsError(try control.loadedLaunchdLabels())

        process.statusByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = 113
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = "Could not find domain"
        XCTAssertThrowsError(try control.loadedLaunchdLabels()) { error in
            guard case .hostFailure(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("domain 错误必须传播，got \(error)")
            }
            XCTAssertTrue(message.contains("Could not find domain"), message)
        }

        process.statusByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] = 127
        process.outputByJoinedArguments["print gui/\(uid)/\(identity.agentLaunchdLabel)"] =
            "launchctl: command not found"
        XCTAssertThrowsError(try control.loadedLaunchdLabels()) { error in
            guard case .hostFailure(let message) = error as? AhaKeyReleaseInstallError else {
                return XCTFail("command 错误必须传播，got \(error)")
            }
            XCTAssertTrue(message.contains("command not found"), message)
        }
    }

    func testPlistPostRenameFailuresRestoreOldPresentAndOldAbsent() throws {
        let phases: [AhaKeyReleaseWriteFailurePoint] = [
            .afterRename, .afterDirectoryFsync, .afterFinalFsync,
        ]
        for phase in phases {
            try assertPlistRestored(oldPresent: true, failAt: phase)
            try assertPlistRestored(oldPresent: false, failAt: phase)
        }
    }

    private func assertPlistRestored(oldPresent: Bool, failAt: AhaKeyReleaseWriteFailurePoint) throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = (root as NSString).appendingPathComponent("LaunchAgents/lab.jawa.ahakeyconfig.agent.plist")
        let host = AhaKeyReleaseMacInstallHost(system: AhaKeyReleaseRecordingSystemControl())
        if oldPresent {
            try host.writeFile(at: path, data: Data("original-bytes".utf8))
        }
        host.injectedWriteFailure = failAt
        XCTAssertThrowsError(try host.writeFile(at: path, data: Data("new-bytes".utf8)))
        if oldPresent {
            XCTAssertEqual(host.readFile(at: path), Data("original-bytes".utf8))
        } else {
            XCTAssertNil(host.readFile(at: path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        }
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: (path as NSString).deletingLastPathComponent
        ).filter { $0.hasPrefix(".ahakey-") && $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "\(failAt) leftover=\(leftovers) oldPresent=\(oldPresent)")
    }

    func testPlistBackupAndCleanupFailuresDoNotFalselySucceed() throws {
        try assertPlistSeam(
            oldPresent: true,
            failAt: .backupCreate,
            expectedContents: Data("original-bytes".utf8),
            expectRollbackFailed: false,
            expectLeftovers: false
        )
        try assertPlistSeam(
            oldPresent: true,
            failAt: .backupRead,
            expectedContents: Data("original-bytes".utf8),
            expectRollbackFailed: false,
            expectLeftovers: false
        )
        try assertPlistSeam(
            oldPresent: false,
            failAt: .restoreUnlink,
            expectedContents: Data("new-bytes".utf8),
            expectRollbackFailed: true,
            expectLeftovers: false
        )
        try assertPlistSeam(
            oldPresent: true,
            failAt: .successCleanup,
            expectedContents: Data("new-bytes".utf8),
            expectRollbackFailed: true,
            expectLeftovers: false
        )
    }

    private func assertPlistSeam(
        oldPresent: Bool,
        failAt: AhaKeyReleaseWriteFailurePoint,
        expectedContents: Data?,
        expectRollbackFailed: Bool,
        expectLeftovers: Bool
    ) throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = (root as NSString).appendingPathComponent("LaunchAgents/lab.jawa.ahakeyconfig.agent.plist")
        let directory = (path as NSString).deletingLastPathComponent
        let host = AhaKeyReleaseMacInstallHost(system: AhaKeyReleaseRecordingSystemControl())
        if oldPresent {
            try host.writeFile(at: path, data: Data("original-bytes".utf8))
        }
        host.injectedWriteFailure = failAt
        XCTAssertThrowsError(try host.writeFile(at: path, data: Data("new-bytes".utf8))) { error in
            if expectRollbackFailed {
                guard case .rollbackFailed = error as? AhaKeyReleaseInstallError else {
                    return XCTFail("\(failAt) expected rollbackFailed, got \(error)")
                }
            } else {
                guard case .hostFailure = error as? AhaKeyReleaseInstallError else {
                    return XCTFail("\(failAt) expected hostFailure, got \(error)")
                }
            }
        }
        XCTAssertEqual(host.readFile(at: path), expectedContents, "\(failAt)")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasPrefix(".ahakey-") && $0.hasSuffix(".tmp") }
        if expectLeftovers {
            XCTAssertFalse(leftovers.isEmpty, "\(failAt) expected leftover backup")
        } else {
            XCTAssertTrue(leftovers.isEmpty, "\(failAt) leftover=\(leftovers)")
        }
    }

    private struct AppFixture {
        var app: String
        var parent: String
    }

    private func makeTempRoot() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ahakey-5.9a-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func customTestIdentity() -> AhaKeyReleaseIdentity {
        let current = identity
        return AhaKeyReleaseIdentity(
            channel: current.channel,
            productVersion: current.productVersion,
            bundleIdentifier: current.bundleIdentifier,
            signingIdentifier: current.signingIdentifier,
            teamIdentifier: current.teamIdentifier,
            appDisplayName: current.appDisplayName,
            appBundleFileName: current.appBundleFileName,
            executableName: current.executableName,
            agentBinaryName: "custom-agent",
            agentLaunchdLabel: "lab.test.custom.agent",
            hilLaunchdLabel: "lab.test.custom.agent.hil",
            machServiceName: current.machServiceName,
            minimumDarwinMajor: current.minimumDarwinMajor,
            minimumMacOSVersion: current.minimumMacOSVersion
        )
    }

    private func macosNames(in app: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: (app as NSString).appendingPathComponent("Contents/MacOS")
        ).sorted()
    }

    private func makeAppFixture(
        in root: String,
        name: String,
        marker: String,
        identity: AhaKeyReleaseIdentity? = nil
    ) throws -> AppFixture {
        let identity = identity ?? self.identity
        let parent = (root as NSString).appendingPathComponent("pack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let app = (parent as NSString).appendingPathComponent(name)
        let macos = (app as NSString).appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(atPath: macos, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identity.bundleIdentifier,
            "CFBundleExecutable": identity.executableName,
            "LSMinimumSystemVersion": identity.minimumMacOSVersion,
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: URL(fileURLWithPath: (app as NSString).appendingPathComponent("Contents/Info.plist")))
        let agent = identity.agentBinaryPath(inApp: app)
        let executable = identity.executablePath(inApp: app)
        let trueBin = "/usr/bin/true"
        try FileManager.default.copyItem(atPath: trueBin, toPath: agent)
        try FileManager.default.copyItem(atPath: trueBin, toPath: executable)
        let resources = (app as NSString).appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true)
        try Data(marker.utf8).write(
            to: URL(fileURLWithPath: (resources as NSString).appendingPathComponent("ahakey-tree-marker"))
        )
        try codesignAdHoc(agent)
        try codesignAdHoc(executable)
        try codesignAdHoc(app)
        let plist = try identity.launchAgentPlist(
            agentBinaryPath: agent,
            socketPath: "/tmp/s",
            logPath: "/tmp/l"
        )
        try plist.write(to: URL(fileURLWithPath: (parent as NSString).appendingPathComponent("LaunchAgent.plist")))
        return AppFixture(app: app, parent: parent)
    }

    private func codesignAdHoc(_ path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--force", "--sign", "-", "--identifier", identity.signingIdentifier, path,
        ]
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "codesign ad-hoc failed for \(path): \(err)")
    }

    private func tamperAppSeal(_ app: String) throws {
        let resources = (app as NSString).appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true)
        try Data("tamper".utf8).write(
            to: URL(fileURLWithPath: (resources as NSString).appendingPathComponent("broken.txt"))
        )
    }
}

/// 测试专用：在终态 snapshot 前把**实际安装路径**替换为错树。生产 Host 无此 seam。
private final class TerminalTreeMutatingHost: AhaKeyReleaseInstallHost {
    let inner: AhaKeyReleaseMacInstallHost
    let wrongTreePath: String
    private var snapshotCount = 0

    init(inner: AhaKeyReleaseMacInstallHost, wrongTreePath: String) {
        self.inner = inner
        self.wrongTreePath = wrongTreePath
    }

    var identity: AhaKeyReleaseIdentity { inner.identity }

    func snapshot(layout: AhaKeyReleaseInstallLayout) throws -> AhaKeyReleaseHostSnapshot {
        snapshotCount += 1
        if snapshotCount > 1 {
            try replaceInstallTree(layout.applicationsAppPath)
        }
        return try inner.snapshot(layout: layout)
    }

    func inspectCandidate(at appPath: String, identity: AhaKeyReleaseIdentity) throws -> AhaKeyReleaseCandidateReport {
        try inner.inspectCandidate(at: appPath, identity: identity)
    }

    func appFingerprint(at path: String) throws -> String {
        try inner.appFingerprint(at: path)
    }

    func itemExists(at path: String) -> Bool { inner.itemExists(at: path) }
    func isSymlink(_ path: String) -> Bool { inner.isSymlink(path) }
    func resolvedPath(_ path: String) -> String? { inner.resolvedPath(path) }

    func replaceDirectoryAtomically(from: String, to: String, backup: String, staging: String) throws {
        try inner.replaceDirectoryAtomically(from: from, to: to, backup: backup, staging: staging)
    }

    func moveDirectoryAtomically(from: String, to: String) throws {
        try inner.moveDirectoryAtomically(from: from, to: to)
    }

    func removeTree(_ path: String) throws { try inner.removeTree(path) }
    func writeFile(at path: String, data: Data) throws { try inner.writeFile(at: path, data: data) }
    func readFile(at path: String) -> Data? { inner.readFile(at: path) }
    func bootout(label: String) throws { try inner.bootout(label: label) }
    func bootstrap(label: String, plistPath: String) throws { try inner.bootstrap(label: label, plistPath: plistPath) }
    func registerLoginItem() throws { try inner.registerLoginItem() }
    func unregisterLoginItem() throws { try inner.unregisterLoginItem() }
    func disabledLaunchdLabels() throws -> Set<String> { try inner.disabledLaunchdLabels() }
    func setLaunchdDisabled(label: String, disabled: Bool) throws {
        try inner.setLaunchdDisabled(label: label, disabled: disabled)
    }

    private func replaceInstallTree(_ destination: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination) {
            try fm.removeItem(atPath: destination)
        }
        try fm.copyItem(atPath: wrongTreePath, toPath: destination)
    }
}
