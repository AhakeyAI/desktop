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
        process.statusByJoinedArguments["print gui/\(uid)/\(identity.hilLaunchdLabel)"] = 1
        let control = AhaKeyReleaseLaunchdControl(allowSystemMutation: false, process: process)
        XCTAssertEqual(try control.loadedLaunchdLabels(), [identity.agentLaunchdLabel])
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

    private struct AppFixture {
        var app: String
        var parent: String
    }

    private func makeTempRoot() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ahakey-5.9a-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func makeAppFixture(in root: String, name: String, marker: String) throws -> AppFixture {
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
        _ = marker
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
}
