import Foundation

public enum FirmwareCatalogIdentity: Equatable, Sendable {
    case readFailed
    case legacy
    case key(String)
}

public struct FirmwareDesktopContext: Equatable, Sendable {
    public let version: FirmwareDesktopVersion
    public let variant: String
    public let hardware: String
    public let allowedChannels: Set<FirmwareReleaseCatalog.Channel>
    public init(version: FirmwareDesktopVersion, variant: String = "legacy-macos", hardware: String = "x1-c582-hw1",
        allowedChannels: Set<FirmwareReleaseCatalog.Channel> = [.stable]) {
        self.version = version; self.variant = variant; self.hardware = hardware; self.allowedChannels = allowedChannels
    }
}

public enum FirmwareCatalogState: Equatable, Sendable {
    case ready
    case legacy
    case keyReadFailed
    case unknownKey(String)
    case catalogUnavailable
    case desktopTooOld(required: String)
    case unsupportedVariant
    case unsupportedHardware
    case unsupportedProtocol
}

public struct FirmwareCatalogDecision: Equatable, Sendable {
    public let state: FirmwareCatalogState
    public let capabilities: Set<FirmwareReleaseCatalog.Capability>
    public var permitsAdvancedOperations: Bool { state == .ready }
    public init(state: FirmwareCatalogState, capabilities: Set<FirmwareReleaseCatalog.Capability> = []) {
        self.state = state; self.capabilities = state == .ready ? capabilities : []
    }
    public static func evaluate(identity: FirmwareCatalogIdentity, catalog: VerifiedFirmwareCatalog?, context: FirmwareDesktopContext) -> Self {
        switch identity {
        case .readFailed: return Self(state: .keyReadFailed)
        case .legacy: return Self(state: .legacy)
        case .key(let key):
            guard let catalog else { return Self(state: .catalogUnavailable) }
            guard let entry = catalog.value.entries.first(where: { $0.key == key }) else { return Self(state: .unknownKey(key)) }
            let state = compatibility(entry, context: context)
            return Self(state: state, capabilities: entry.capabilities)
        }
    }
    public static func compatibility(_ entry: FirmwareReleaseCatalog.Entry, context: FirmwareDesktopContext) -> FirmwareCatalogState {
        guard entry.hardware == context.hardware else { return .unsupportedHardware }
        guard entry.desktopVariants.contains(context.variant) else { return .unsupportedVariant }
        // Catalog signatures do not make an unimplemented wire protocol usable.
        guard entry.protocolProfile == "p1" else { return .unsupportedProtocol }
        guard let minimum = FirmwareDesktopVersion(entry.minimumDesktop), context.version >= minimum else {
            return .desktopTooOld(required: entry.minimumDesktop)
        }
        return .ready
    }
}

public struct FirmwareInstallCandidate: Equatable, Sendable {
    public enum Badge: String, Hashable, Sendable { case recommended, latest, stableRecovery, current }
    public let entry: FirmwareReleaseCatalog.Entry
    public let badges: Set<Badge>
    public let compatibility: FirmwareCatalogState
    public var canInstall: Bool { compatibility == .ready }
}

public enum FirmwareCandidateSelection {
    /// A prepared file belongs to the complete candidate, not merely its key.
    /// Catalog refreshes can revoke or replace an artifact under that identity.
    public static func isCurrent(_ prepared: FirmwareInstallCandidate, in candidates: [FirmwareInstallCandidate]) -> Bool {
        prepared.canInstall && candidates.contains(prepared)
    }
    /// One validated key, one row, possibly several labels. Public candidates
    /// never come from an unverified local HEX or an engineering profile.
    public static func candidates(catalog: VerifiedFirmwareCatalog?, identity: FirmwareCatalogIdentity,
        context: FirmwareDesktopContext) -> [FirmwareInstallCandidate] {
        guard let catalog else { return [] }
        let entries = catalog.value.entries.filter {
            $0.visibility == .user && $0.hardware == context.hardware && $0.desktopVariants.contains(context.variant) &&
                context.allowedChannels.contains($0.channel) && $0.artifact != nil
        }.sorted {
            $0.releaseOrder == $1.releaseOrder ? $0.key < $1.key : $0.releaseOrder > $1.releaseOrder
        }
        let compatibleStable = entries.filter { $0.channel == .stable && FirmwareCatalogDecision.compatibility($0, context: context) == .ready }
        let recommended = compatibleStable.first(where: \.recommended) ?? compatibleStable.first
        let recovery = compatibleStable.first(where: \.recoverySafe)
        let current: String?
        if case .key(let key) = identity { current = key } else { current = nil }
        return entries.map { entry in
            var badges: Set<FirmwareInstallCandidate.Badge> = []
            if entry.key == recommended?.key { badges.insert(.recommended) }
            if entry.key == entries.first?.key { badges.insert(.latest) }
            if entry.key == recovery?.key { badges.insert(.stableRecovery) }
            if entry.key == current { badges.insert(.current) }
            let compatibility: FirmwareCatalogState
            if identity == .readFailed { compatibility = .keyReadFailed }
            else { compatibility = FirmwareCatalogDecision.compatibility(entry, context: context) }
            return FirmwareInstallCandidate(entry: entry, badges: badges, compatibility: compatibility)
        }
    }
    public static func trustedLocalMatch(sha256: String, catalog: VerifiedFirmwareCatalog?, context: FirmwareDesktopContext) -> FirmwareReleaseCatalog.Entry? {
        guard FirmwareReleaseCatalog.validDigest(sha256), let catalog else { return nil }
        let matches = catalog.value.entries.filter {
            $0.artifact?.sha256 == sha256 && $0.visibility == .user && $0.channel == .stable &&
                FirmwareCatalogDecision.compatibility($0, context: context) == .ready
        }
        // The same bytes assigned to multiple identities cannot identify the
        // expected post-flash key. Keep this as an unverified local image.
        return matches.count == 1 ? matches[0] : nil
    }
}
