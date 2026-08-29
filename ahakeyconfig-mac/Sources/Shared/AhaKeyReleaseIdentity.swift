import Foundation

/// v0.2 发布身份。唯一运行时来源是嵌入的 `ReleaseIdentity.json`；
/// `Packaging/ReleaseIdentity.json` 必须与此字节级一致（由 check-release-identity.sh 门禁）。
public struct AhaKeyReleaseIdentity: Equatable, Sendable {
    public static let current: AhaKeyReleaseIdentity = {
        do {
            return try AhaKeyReleaseIdentity(jsonUTF8: Data(AhaKeyReleaseIdentityDocument.json.utf8))
        } catch {
            preconditionFailure("embedded ReleaseIdentity.json is invalid: \(error)")
        }
    }()

    public let channel: AhaKeyReleaseChannel
    public let productVersion: String
    public let bundleIdentifier: String
    public let signingIdentifier: String
    public let teamIdentifier: String
    public let appDisplayName: String
    public let appBundleFileName: String
    public let executableName: String
    public let agentBinaryName: String
    public let agentLaunchdLabel: String
    public let hilLaunchdLabel: String
    public let machServiceName: String
    /// macOS 13 Ventura = Darwin 22。低于此版本安装器必须拒绝，不得半安装。
    public let minimumDarwinMajor: Int
    public let minimumMacOSVersion: String

    public init(
        channel: AhaKeyReleaseChannel,
        productVersion: String,
        bundleIdentifier: String,
        signingIdentifier: String,
        teamIdentifier: String,
        appDisplayName: String,
        appBundleFileName: String,
        executableName: String,
        agentBinaryName: String,
        agentLaunchdLabel: String,
        hilLaunchdLabel: String,
        machServiceName: String,
        minimumDarwinMajor: Int,
        minimumMacOSVersion: String
    ) {
        self.channel = channel
        self.productVersion = productVersion
        self.bundleIdentifier = bundleIdentifier
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.appDisplayName = appDisplayName
        self.appBundleFileName = appBundleFileName
        self.executableName = executableName
        self.agentBinaryName = agentBinaryName
        self.agentLaunchdLabel = agentLaunchdLabel
        self.hilLaunchdLabel = hilLaunchdLabel
        self.machServiceName = machServiceName
        self.minimumDarwinMajor = minimumDarwinMajor
        self.minimumMacOSVersion = minimumMacOSVersion
    }

    public init(jsonUTF8 data: Data) throws {
        let decoded = try JSONDecoder().decode(AhaKeyReleaseIdentityRecord.self, from: data)
        guard decoded.channel == "v0.2" else {
            throw AhaKeyReleaseIdentityError.unsupportedChannel(decoded.channel)
        }
        let fields = [
            decoded.productVersion,
            decoded.bundleIdentifier,
            decoded.signingIdentifier,
            decoded.teamIdentifier,
            decoded.appDisplayName,
            decoded.appBundleFileName,
            decoded.executableName,
            decoded.agentBinaryName,
            decoded.agentLaunchdLabel,
            decoded.hilLaunchdLabel,
            decoded.machServiceName,
            decoded.minimumMacOSVersion,
        ]
        if fields.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw AhaKeyReleaseIdentityError.emptyField
        }
        self.init(
            channel: .v0_2,
            productVersion: decoded.productVersion,
            bundleIdentifier: decoded.bundleIdentifier,
            signingIdentifier: decoded.signingIdentifier,
            teamIdentifier: decoded.teamIdentifier,
            appDisplayName: decoded.appDisplayName,
            appBundleFileName: decoded.appBundleFileName,
            executableName: decoded.executableName,
            agentBinaryName: decoded.agentBinaryName,
            agentLaunchdLabel: decoded.agentLaunchdLabel,
            hilLaunchdLabel: decoded.hilLaunchdLabel,
            machServiceName: decoded.machServiceName,
            minimumDarwinMajor: decoded.minimumDarwinMajor,
            minimumMacOSVersion: decoded.minimumMacOSVersion
        )
        if decoded.developerIDRequirement != developerIDRequirement {
            throw AhaKeyReleaseIdentityError.requirementMismatch
        }
    }

    /// 与生产 XPC peer requirement 同形：HIL 签名时使用，本卡不实际 codesign。
    public var developerIDRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and (identifier \"\(signingIdentifier)\")"
    }

    public func agentBinaryPath(inApp appPath: String) -> String {
        (appPath as NSString).appendingPathComponent("Contents/MacOS/\(agentBinaryName)")
    }

    public func executablePath(inApp appPath: String) -> String {
        (appPath as NSString).appendingPathComponent("Contents/MacOS/\(executableName)")
    }

    public func launchAgentPlist(
        agentBinaryPath: String,
        socketPath: String,
        logPath: String
    ) throws -> Data {
        let dict: [String: Any] = [
            "Label": agentLaunchdLabel,
            "ProgramArguments": [agentBinaryPath, "--socket", socketPath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "MachServices": [machServiceName: true],
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    public func launchAgentDeclaresMachService(_ plist: Data) -> Bool {
        guard let obj = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
              let dict = obj as? [String: Any],
              let services = dict["MachServices"] as? [String: Any]
        else { return false }
        return services[machServiceName] as? Bool == true
            && dict["Label"] as? String == agentLaunchdLabel
    }

    public func isAhaKeyLaunchdLabel(_ label: String) -> Bool {
        label == agentLaunchdLabel
            || label == hilLaunchdLabel
            || label.hasPrefix("lab.jawa.ahakeyconfig.")
    }
}

public enum AhaKeyReleaseIdentityError: Error, Equatable {
    case unsupportedChannel(String)
    case emptyField
    case requirementMismatch
}

private struct AhaKeyReleaseIdentityRecord: Decodable {
    var channel: String
    var productVersion: String
    var bundleIdentifier: String
    var signingIdentifier: String
    var teamIdentifier: String
    var appDisplayName: String
    var appBundleFileName: String
    var executableName: String
    var agentBinaryName: String
    var agentLaunchdLabel: String
    var hilLaunchdLabel: String
    var machServiceName: String
    var minimumDarwinMajor: Int
    var minimumMacOSVersion: String
    var developerIDRequirement: String
}

enum AhaKeyReleaseIdentityDocument {
    // RELEASE-IDENTITY-JSON-BEGIN
    static let json = #"""
{
  "channel": "v0.2",
  "productVersion": "0.2.0",
  "bundleIdentifier": "lab.jawa.ahakeyconfig",
  "signingIdentifier": "lab.jawa.ahakeyconfig",
  "teamIdentifier": "P2VFVRZK7P",
  "appDisplayName": "AhaKey Studio",
  "appBundleFileName": "AhaKey Studio.app",
  "executableName": "AhaKeyConfig",
  "agentBinaryName": "ahakeyconfig-agent",
  "agentLaunchdLabel": "lab.jawa.ahakeyconfig.agent",
  "hilLaunchdLabel": "lab.jawa.ahakeyconfig.agent.hil",
  "machServiceName": "lab.jawa.ahakeyconfig.runtime",
  "minimumDarwinMajor": 22,
  "minimumMacOSVersion": "13.0",
  "developerIDRequirement": "anchor apple generic and certificate leaf[subject.OU] = \"P2VFVRZK7P\" and (identifier \"lab.jawa.ahakeyconfig\")"
}
"""#
    // RELEASE-IDENTITY-JSON-END
}

public enum AhaKeyReleaseSignatureKind: String, Equatable, Sendable {
    case adhoc
    case developerID
    case unknown
}

/// 未签名候选或未来 Developer ID 输入的静态检查结果。本卡只证明清单，不调用 codesign。
public enum AhaKeyReleaseSigningCheck: Equatable, Sendable {
    case unsignedCandidateReady
    case signedIdentityMatches
    case rejected(AhaKeyReleaseSigningRejection)
}

public enum AhaKeyReleaseSigningRejection: Equatable, Sendable {
    case candidateNotInspected
    case missingBundleIdentifier
    case bundleIdentifierMismatch(found: String)
    case missingAgentBinary
    case machServiceMissing
    case missingTeamIdentifier
    case teamIdentifierMismatch(found: String)
    case missingSigningIdentifier
    case signingIdentifierMismatch(found: String)
    case unexpectedDeveloperID
    case unsignedCandidateNotAdHoc
}

public struct AhaKeyReleaseCandidateReport: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var agentBinaryPresent: Bool
    public var launchAgentPlist: Data?
    public var teamIdentifier: String?
    public var signingIdentifier: String?
    public var signatureKind: AhaKeyReleaseSignatureKind

    public init(
        bundleIdentifier: String?,
        agentBinaryPresent: Bool,
        launchAgentPlist: Data?,
        teamIdentifier: String? = nil,
        signingIdentifier: String? = nil,
        signatureKind: AhaKeyReleaseSignatureKind = .unknown
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.agentBinaryPresent = agentBinaryPresent
        self.launchAgentPlist = launchAgentPlist
        self.teamIdentifier = teamIdentifier
        self.signingIdentifier = signingIdentifier
        self.signatureKind = signatureKind
    }
}

public enum AhaKeyReleaseSigningChecklist {
    public static func check(
        _ report: AhaKeyReleaseCandidateReport?,
        identity: AhaKeyReleaseIdentity = .current
    ) -> AhaKeyReleaseSigningCheck {
        guard let report else {
            return .rejected(.candidateNotInspected)
        }
        guard let bundleID = nonempty(report.bundleIdentifier) else {
            return .rejected(.missingBundleIdentifier)
        }
        if bundleID != identity.bundleIdentifier {
            return .rejected(.bundleIdentifierMismatch(found: bundleID))
        }
        guard report.agentBinaryPresent else {
            return .rejected(.missingAgentBinary)
        }
        guard let plist = report.launchAgentPlist, identity.launchAgentDeclaresMachService(plist) else {
            return .rejected(.machServiceMissing)
        }
        guard let signing = nonempty(report.signingIdentifier) else {
            return .rejected(.missingSigningIdentifier)
        }
        if signing != identity.signingIdentifier {
            return .rejected(.signingIdentifierMismatch(found: signing))
        }

        switch report.signatureKind {
        case .adhoc:
            if nonempty(report.teamIdentifier) != nil {
                return .rejected(.unexpectedDeveloperID)
            }
            return .unsignedCandidateReady
        case .developerID:
            guard let team = nonempty(report.teamIdentifier) else {
                return .rejected(.missingTeamIdentifier)
            }
            if team != identity.teamIdentifier {
                return .rejected(.teamIdentifierMismatch(found: team))
            }
            return .signedIdentityMatches
        case .unknown:
            return .rejected(.unsignedCandidateNotAdHoc)
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-" || trimmed == "not set" {
            return nil
        }
        return trimmed
    }
}
