import Foundation

/// A catalog key selects a verified protocol contract, not a particular HEX build.
/// Unknown keys stay read-only until their behavior has been checked against a
/// firmware commit and an actual device.
public struct FirmwareCapabilityProfile: Equatable {
    public enum Identity: Equatable {
        case knownWS2Catalog
        case verifiedCatalog(String, Set<FirmwareReleaseCatalog.Capability>)
        case legacy
        case unknown(String?)
    }

    public let identity: Identity

    public static let ws2CatalogKey = "x1-c582-hw1-p1-1.0.0-r001"

    public static func catalogResponse(_ frame: Data, catalog: VerifiedFirmwareCatalog? = .builtin,
        context: FirmwareDesktopContext = .init(version: FirmwareDesktopVersion("0.0.0")!)) -> FirmwareCapabilityProfile {
        let bytes = [UInt8](frame)
        guard bytes.count >= 7,
              bytes[0] == 0xAA, bytes[1] == 0xBB,
              bytes[2] == 0x9F, bytes[3] == 0x00,
              bytes[bytes.count - 2] == 0xCC, bytes[bytes.count - 1] == 0xDD,
              let key = String(bytes: bytes[4..<(bytes.count - 2)], encoding: .ascii),
              !key.isEmpty else {
            return FirmwareCapabilityProfile(identity: .unknown(nil))
        }
        let decision = FirmwareCatalogDecision.evaluate(identity: .key(key), catalog: catalog, context: context)
        guard decision.permitsAdvancedOperations,
              catalog?.value.entries.first(where: { $0.key == key })?.visibility != .factory else {
            return FirmwareCapabilityProfile(identity: .unknown(key))
        }
        if key == ws2CatalogKey, decision.capabilities == VerifiedFirmwareCatalog.builtin?.value.entries.first?.capabilities {
            return FirmwareCapabilityProfile(identity: .knownWS2Catalog)
        }
        return FirmwareCapabilityProfile(identity: .verifiedCatalog(key, decision.capabilities))
    }

    /// A short generic success ACK is the only verified legacy fallback. A device
    /// rejection, timeout or malformed frame is never evidence of an older device.
    /// The caller must also have a valid status from this same connection.
    public static func probeResponse(_ frame: Data, hasValidStatusReadback: Bool,
        catalog: VerifiedFirmwareCatalog? = .builtin,
        context: FirmwareDesktopContext = .init(version: FirmwareDesktopVersion("0.0.0")!)) -> FirmwareCapabilityProfile {
        guard hasValidStatusReadback else { return FirmwareCapabilityProfile(identity: .unknown(nil)) }
        if frame == Data([0xAA, 0xBB, 0x9F, 0, 0xCC, 0xDD]) {
            return legacyAfterStatusReadback()
        }
        return catalogResponse(frame, catalog: catalog, context: context)
    }

    /// Construct a legacy profile only after the probe validated the exact generic
    /// success ACK and an independent status from the same connection.
    public static func legacyAfterStatusReadback() -> FirmwareCapabilityProfile {
        FirmwareCapabilityProfile(identity: .legacy)
    }

    // These flags permit read-only probes. A matching catalog key alone does
    // not prove the build SHA or authorize writes; each editor must also have
    // a successful device readback for the setting it changes.
    public var catalogKey: String? {
        switch identity {
        case .knownWS2Catalog: return Self.ws2CatalogKey
        case .verifiedCatalog(let key, _), .unknown(let key?): return key
        default: return nil
        }
    }
    public var isVerifiedProtocol: Bool {
        switch identity { case .knownWS2Catalog, .verifiedCatalog: return true; default: return false }
    }
    public func supports(_ capability: FirmwareReleaseCatalog.Capability) -> Bool {
        switch identity {
        case .knownWS2Catalog: return true
        case .verifiedCatalog(_, let capabilities): return capabilities.contains(capability)
        default: return false
        }
    }
    public var mayQueryOrdinaryKeys: Bool { supports(.ordinaryKeys) }
    public var mayQueryVoiceOnboarding: Bool { supports(.voiceOnboarding) }
    public var mayQuerySideSwitchBindings: Bool { supports(.sideSwitchBindings) }
    public var mayQueryStandby: Bool { supports(.standby) }
    public var mayQueryWS3Display: Bool { supports(.ws3Display) }
    public var mayQueryWS3Resources: Bool { supports(.ws3Display) && supports(.ws3Resources) }
    public var mayUseWS3Presentation: Bool { supports(.ws3Display) && supports(.ws3Presentation) }
    public var canWriteWithoutReadback: Bool { false }
    public var canUseWS3Presentation: Bool { false }
    public var canWriteWS3Resources: Bool { false }
}
