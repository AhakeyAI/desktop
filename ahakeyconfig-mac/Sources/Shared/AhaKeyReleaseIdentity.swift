import Foundation

/// v0.2 发布身份。Bundle ID、Team ID、Signing ID 与 Mach service 只在此处冻结；
/// 安装器、打包脚本与 XPC peer 策略必须与此一致。
public struct AhaKeyReleaseIdentity: Equatable, Sendable {
    public static let current = AhaKeyReleaseIdentity()

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
        channel: AhaKeyReleaseChannel = .v0_2,
        productVersion: String = "0.2.0",
        bundleIdentifier: String = "lab.jawa.ahakeyconfig",
        signingIdentifier: String = "lab.jawa.ahakeyconfig",
        teamIdentifier: String = "P2VFVRZK7P",
        appDisplayName: String = "AhaKey Studio",
        appBundleFileName: String = "AhaKey Studio.app",
        executableName: String = "AhaKeyConfig",
        agentBinaryName: String = "ahakeyconfig-agent",
        agentLaunchdLabel: String = "lab.jawa.ahakeyconfig.agent",
        hilLaunchdLabel: String = "lab.jawa.ahakeyconfig.agent.hil",
        machServiceName: String = "lab.jawa.ahakeyconfig.runtime",
        minimumDarwinMajor: Int = 22,
        minimumMacOSVersion: String = "13.0"
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

    /// 与生产 XPC peer requirement 同形：HIL 签名时使用，本卡不实际 codesign。
    public var developerIDRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and (identifier \"\(signingIdentifier)\")"
    }

    public func agentBinaryPath(inApp appPath: String) -> String {
        (appPath as NSString).appendingPathComponent("Contents/MacOS/\(agentBinaryName)")
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
}

/// 未签名候选或未来 Developer ID 输入的静态检查结果。本卡只证明清单，不调用 codesign。
public enum AhaKeyReleaseSigningCheck: Equatable, Sendable {
    case unsignedCandidateReady
    case signedIdentityMatches
    case rejected(AhaKeyReleaseSigningRejection)
}

public enum AhaKeyReleaseSigningRejection: Equatable, Sendable {
    case missingBundleIdentifier
    case bundleIdentifierMismatch(found: String)
    case missingAgentBinary
    case machServiceMissing
    case teamIdentifierMismatch(found: String)
    case signingIdentifierMismatch(found: String)
}

public struct AhaKeyReleaseCandidateReport: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var agentBinaryPresent: Bool
    public var launchAgentPlist: Data?
    public var teamIdentifier: String?
    public var signingIdentifier: String?
    public var signedWithDeveloperID: Bool

    public init(
        bundleIdentifier: String?,
        agentBinaryPresent: Bool,
        launchAgentPlist: Data?,
        teamIdentifier: String? = nil,
        signingIdentifier: String? = nil,
        signedWithDeveloperID: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.agentBinaryPresent = agentBinaryPresent
        self.launchAgentPlist = launchAgentPlist
        self.teamIdentifier = teamIdentifier
        self.signingIdentifier = signingIdentifier
        self.signedWithDeveloperID = signedWithDeveloperID
    }
}

public enum AhaKeyReleaseSigningChecklist {
    public static func check(
        _ report: AhaKeyReleaseCandidateReport,
        identity: AhaKeyReleaseIdentity = .current
    ) -> AhaKeyReleaseSigningCheck {
        guard let bundleID = report.bundleIdentifier, !bundleID.isEmpty else {
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
        if report.signedWithDeveloperID {
            if let team = report.teamIdentifier, team != identity.teamIdentifier {
                return .rejected(.teamIdentifierMismatch(found: team))
            }
            if let signing = report.signingIdentifier, signing != identity.signingIdentifier {
                return .rejected(.signingIdentifierMismatch(found: signing))
            }
            return .signedIdentityMatches
        }
        return .unsignedCandidateReady
    }
}
