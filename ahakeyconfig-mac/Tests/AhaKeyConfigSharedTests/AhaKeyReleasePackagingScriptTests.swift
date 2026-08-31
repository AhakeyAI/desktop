import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyReleasePackagingScriptTests: XCTestCase {

    private let identity = AhaKeyReleaseIdentity.current
    private let fileManager = FileManager.default

    func testPackageDMGResignsWithFrozenIdentifierAndCompanionPlist() throws {
        let script = try String(contentsOf: packageDMGURL(), encoding: .utf8)
        XCTAssertGreaterThanOrEqual(
            script.components(separatedBy: "--identifier \"$SIGNING_IDENTIFIER\"").count - 1,
            2
        )
        XCTAssertTrue(script.contains("release_identity.py"))
        XCTAssertTrue(script.contains(" env "))
        XCTAssertFalse(script.contains("json.loads"))
        XCTAssertFalse(script.contains("$DMG_STAGING_DIR/$APP_BUNDLE_FILE_NAME"))
        XCTAssertFalse(script.contains("\"$DMG_STAGING_DIR/LaunchAgent.plist\""))
        XCTAssertTrue(script.contains("Packaging/LaunchAgent.plist"))
        XCTAssertTrue(script.contains("LaunchAgent.plist"))
        XCTAssertTrue(script.contains("verify-release-dmg.sh"))
        XCTAssertTrue(script.contains("Product identity gate (pre-notarization)"))
        XCTAssertTrue(script.contains("Product identity gate (post-staple)"))
        XCTAssertFalse(script.contains("Contents/MacOS/ahakeyconfig-agent\""))
        XCTAssertTrue(script.contains("Contents/MacOS/$AGENT_BINARY_NAME"))
        XCTAssertFalse(script.contains("lab.jawa.ahakeyconfig"))
        XCTAssertFalse(script.contains("P2VFVRZK7P"))
    }

    func testPackReleaseWiresIdentityCheckAndPackageDMG() throws {
        let script = try String(contentsOf: packReleaseURL(), encoding: .utf8)
        XCTAssertTrue(script.contains("check-release-identity.sh"))
        XCTAssertTrue(script.contains("package_dmg.sh"))
        XCTAssertTrue(script.contains("verify-release-dmg.sh"))
    }

    func testMatchingVolumeFixturePasses() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("release dmg volume ok"))
    }

    func testMatchingVolumeFailsClosedUnderReleaseDeveloperIDGate() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        let result = try runVerifier(root: root, expectDeveloperID: true)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Team ID") || result.output.contains("requirement"),
            result.output
        )
    }

    func testWrongAgentIdentifierFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try codesign(
            identity.agentBinaryPath(inApp: appPath(in: root)),
            identifier: "ahakeyconfig-agent"
        )
        try codesign(appPath(in: root), identifier: identity.signingIdentifier)
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("signing identifier"), result.output)
    }

    func testWrongAppIdentifierFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try codesign(appPath(in: root), identifier: "lab.jawa.ahakeyconfig.wrong")
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("signing identifier"), result.output)
    }

    func testMissingAgentFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try fileManager.removeItem(atPath: identity.agentBinaryPath(inApp: appPath(in: root)))
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("missing agent"), result.output)
    }

    func testMissingCompanionPlistFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try fileManager.removeItem(atPath: (root as NSString).appendingPathComponent("LaunchAgent.plist"))
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("missing companion"), result.output)
    }

    func testWrongMachServiceFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try mutateCompanion(in: root) { plist in
            plist["MachServices"] = ["lab.jawa.ahakeyconfig.wrong": true]
        }
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("MachServices"), result.output)
    }

    func testAdditiveExtraMachServiceFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try mutateCompanion(in: root) { plist in
            var services = plist["MachServices"] as? [String: Any] ?? [:]
            services["lab.jawa.ahakeyconfig.extra"] = true
            plist["MachServices"] = services
        }
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("MachServices"), result.output)
    }

    func testAdditiveExtraProgramArgumentsFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try mutateCompanion(in: root) { plist in
            var arguments = plist["ProgramArguments"] as? [String] ?? []
            arguments.append("--evil")
            plist["ProgramArguments"] = arguments
        }
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("ProgramArguments"), result.output)
    }

    func testReleaseSignaturePolicyMatchingPasses() throws {
        let result = try runSignaturePolicy(
            identifier: identity.signingIdentifier,
            team: identity.teamIdentifier,
            requirementOK: true,
            expectDeveloperID: true
        )
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("signature policy ok"), result.output)
    }

    func testReleaseSignaturePolicyWrongTeamFailsClosed() throws {
        let result = try runSignaturePolicy(
            identifier: identity.signingIdentifier,
            team: "ABCDEFGHIJ",
            requirementOK: true,
            expectDeveloperID: true
        )
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Team ID"), result.output)
    }

    func testReleaseSignaturePolicyWrongRequirementFailsClosed() throws {
        let result = try runSignaturePolicy(
            identifier: identity.signingIdentifier,
            team: identity.teamIdentifier,
            requirementOK: false,
            expectDeveloperID: true
        )
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("requirement"), result.output)
    }

    func testHiddenExtraAppFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try fileManager.createDirectory(
            atPath: (root as NSString).appendingPathComponent(".Hidden.app"),
            withIntermediateDirectories: true
        )
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("exactly one app"), result.output)
    }

    func testAppSymlinkEscapeFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        let app = appPath(in: root)
        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("ahakey-escape-app-\(UUID().uuidString).app")
            .path
        try fileManager.moveItem(atPath: app, toPath: outside)
        defer { try? fileManager.removeItem(atPath: outside) }
        try fileManager.createSymbolicLink(atPath: app, withDestinationPath: outside)
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("symlink"), result.output)
    }

    func testCompanionSymlinkEscapeFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        let companion = (root as NSString).appendingPathComponent("LaunchAgent.plist")
        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("ahakey-escape-plist-\(UUID().uuidString).plist")
            .path
        try fileManager.moveItem(atPath: companion, toPath: outside)
        defer { try? fileManager.removeItem(atPath: outside) }
        try fileManager.createSymbolicLink(atPath: companion, withDestinationPath: outside)
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("symlink"), result.output)
    }

    func testAgentSymlinkEscapeFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        let agent = identity.agentBinaryPath(inApp: appPath(in: root))
        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("ahakey-escape-agent-\(UUID().uuidString)")
            .path
        try fileManager.moveItem(atPath: agent, toPath: outside)
        defer { try? fileManager.removeItem(atPath: outside) }
        try fileManager.createSymbolicLink(atPath: agent, withDestinationPath: outside)
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("symlink"), result.output)
    }

    func testBrokenSignatureFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        let agent = identity.agentBinaryPath(inApp: appPath(in: root))
        let strip = try run("/usr/bin/codesign", ["--remove-signature", agent])
        XCTAssertEqual(strip.status, 0, strip.output)
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("codesign --verify --strict"), result.output)
    }

    func testWrongVersionFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try writeInfoPlist(inApp: appPath(in: root), version: "0.1.0")
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("CFBundleShortVersionString"), result.output)
    }

    func testExtraAppFailsClosed() throws {
        let root = try makeMatchingVolume()
        defer { try? fileManager.removeItem(atPath: root) }
        try fileManager.createDirectory(
            atPath: (root as NSString).appendingPathComponent("Extra.app"),
            withIntermediateDirectories: true
        )
        let result = try runVerifier(root: root, expectDeveloperID: false)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("exactly one app"), result.output)
    }

    func testMountedMatchingDMGPassesAndBrokenDMGFailsClosed() throws {
        let goodRoot = try makeMatchingVolume()
        let badRoot = try makeMatchingVolume()
        defer {
            try? fileManager.removeItem(atPath: goodRoot)
            try? fileManager.removeItem(atPath: badRoot)
        }
        try fileManager.removeItem(
            atPath: (badRoot as NSString).appendingPathComponent("LaunchAgent.plist")
        )
        let goodDMG = try makeDMG(from: goodRoot)
        let badDMG = try makeDMG(from: badRoot)
        defer {
            try? fileManager.removeItem(atPath: goodDMG)
            try? fileManager.removeItem(atPath: badDMG)
        }

        let good = try runVerifier(dmg: goodDMG, expectDeveloperID: false)
        XCTAssertEqual(good.status, 0, good.output)
        XCTAssertTrue(good.output.contains("release dmg ok"), good.output)

        let bad = try runVerifier(dmg: badDMG, expectDeveloperID: false)
        XCTAssertNotEqual(bad.status, 0, bad.output)
        XCTAssertTrue(bad.output.contains("missing companion"), bad.output)
    }

    func testReleaseIdentityCheckSeesPackagingGate() throws {
        let result = try run("/bin/zsh", [
            appRootURL().appendingPathComponent("scripts/check-release-identity.sh").path,
        ])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("release identity ok"), result.output)
    }

    private func appRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func packageDMGURL() -> URL {
        appRootURL().appendingPathComponent("scripts/package_dmg.sh")
    }

    private func packReleaseURL() -> URL {
        appRootURL().appendingPathComponent("scripts/pack-release.sh")
    }

    private func verifierURL() -> URL {
        appRootURL().appendingPathComponent("scripts/verify-release-dmg.sh")
    }

    private func appPath(in root: String) -> String {
        (root as NSString).appendingPathComponent(identity.appBundleFileName)
    }

    private func makeMatchingVolume() throws -> String {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ahakey-dmg-volume-\(UUID().uuidString)")
            .path
        try fileManager.createDirectory(atPath: root, withIntermediateDirectories: true)
        let app = appPath(in: root)
        let macos = (app as NSString).appendingPathComponent("Contents/MacOS")
        try fileManager.createDirectory(atPath: macos, withIntermediateDirectories: true)
        try writeInfoPlist(inApp: app, version: identity.productVersion)
        let trueBin = "/usr/bin/true"
        try fileManager.copyItem(atPath: trueBin, toPath: identity.agentBinaryPath(inApp: app))
        try fileManager.copyItem(atPath: trueBin, toPath: identity.executablePath(inApp: app))
        try codesign(identity.agentBinaryPath(inApp: app), identifier: identity.signingIdentifier)
        try codesign(identity.executablePath(inApp: app), identifier: identity.signingIdentifier)
        try codesign(app, identifier: identity.signingIdentifier)
        try fileManager.copyItem(
            at: appRootURL().appendingPathComponent("Packaging/LaunchAgent.plist"),
            to: URL(fileURLWithPath: root).appendingPathComponent("LaunchAgent.plist")
        )
        return root
    }

    private func mutateCompanion(in root: String, _ mutate: (inout [String: Any]) -> Void) throws {
        let plistURL = URL(fileURLWithPath: root).appendingPathComponent("LaunchAgent.plist")
        var plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            options: [],
            format: nil
        ) as? [String: Any] ?? [:]
        mutate(&plist)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    private func runSignaturePolicy(
        identifier: String,
        team: String,
        requirementOK: Bool,
        expectDeveloperID: Bool
    ) throws -> (status: Int32, output: String) {
        var arguments = [
            appRootURL().appendingPathComponent("scripts/release_identity.py").path,
            "evaluate-signature-policy",
            appRootURL().path,
            "--identifier", identifier,
            "--team", team,
            "--requirement-ok", requirementOK ? "1" : "0",
        ]
        if expectDeveloperID {
            arguments.append("--expect-developer-id")
        }
        return try run("/usr/bin/env", ["python3"] + arguments)
    }

    private func writeInfoPlist(inApp app: String, version: String) throws {
        let info: [String: Any] = [
            "CFBundleIdentifier": identity.bundleIdentifier,
            "CFBundleExecutable": identity.executableName,
            "CFBundleShortVersionString": version,
            "LSMinimumSystemVersion": identity.minimumMacOSVersion,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: (app as NSString).appendingPathComponent("Contents/Info.plist")))
    }

    private func codesign(_ path: String, identifier: String) throws {
        let result = try run("/usr/bin/codesign", [
            "--force", "--sign", "-", "--identifier", identifier, path,
        ])
        XCTAssertEqual(result.status, 0, "codesign failed for \(path): \(result.output)")
    }

    private func makeDMG(from volumeRoot: String) throws -> String {
        let dmg = fileManager.temporaryDirectory
            .appendingPathComponent("ahakey-verify-\(UUID().uuidString).dmg")
            .path
        let create = try run("/usr/bin/hdiutil", [
            "create", "-volname", "AhaKeyInstaller", "-size", "20m", "-fs", "HFS+", "-ov", dmg,
        ])
        XCTAssertEqual(create.status, 0, create.output)
        let mount = fileManager.temporaryDirectory
            .appendingPathComponent("ahakey-verify-mnt-\(UUID().uuidString)")
            .path
        try fileManager.createDirectory(atPath: mount, withIntermediateDirectories: true)
        let attach = try run("/usr/bin/hdiutil", [
            "attach", dmg, "-mountpoint", mount, "-readwrite", "-nobrowse", "-noverify",
        ])
        XCTAssertEqual(attach.status, 0, attach.output)
        let copy = try run("/usr/bin/ditto", [volumeRoot, mount])
        let detach = try run("/usr/bin/hdiutil", ["detach", mount, "-force"])
        try? fileManager.removeItem(atPath: mount)
        XCTAssertEqual(copy.status, 0, copy.output)
        XCTAssertEqual(detach.status, 0, detach.output)
        return dmg
    }

    @discardableResult
    private func runVerifier(root: String? = nil, dmg: String? = nil, expectDeveloperID: Bool) throws -> (status: Int32, output: String) {
        var args = [verifierURL().path]
        if expectDeveloperID {
            args.append("--expect-developer-id")
        }
        if let root {
            args.append(contentsOf: ["--root", root])
        } else if let dmg {
            args.append(dmg)
        } else {
            return (-1, "missing verifier target")
        }
        return try run("/bin/zsh", args)
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
