import Foundation

/// A catalog key selects a verified protocol contract, not a particular HEX build.
/// Unknown keys stay read-only until their behavior has been checked against a
/// firmware commit and an actual device.
public struct FirmwareCapabilityProfile: Equatable {
    public enum Identity: Equatable {
        case knownWS2Catalog
        case legacy
        case unknown(String?)
    }

    public let identity: Identity

    public static let ws2CatalogKey = "x1-c582-hw1-p1-1.0.0-r001"

    public static func catalogResponse(_ frame: Data) -> FirmwareCapabilityProfile {
        let bytes = [UInt8](frame)
        guard bytes.count >= 7,
              bytes[0] == 0xAA, bytes[1] == 0xBB,
              bytes[2] == 0x9F, bytes[3] == 0x00,
              bytes[bytes.count - 2] == 0xCC, bytes[bytes.count - 1] == 0xDD,
              let key = String(bytes: bytes[4..<(bytes.count - 2)], encoding: .ascii),
              !key.isEmpty else {
            return FirmwareCapabilityProfile(identity: .unknown(nil))
        }
        return FirmwareCapabilityProfile(identity: key == ws2CatalogKey ? .knownWS2Catalog : .unknown(key))
    }

    /// Call only after 0x9F has timed out or proved unsupported and a valid 0x00
    /// status frame has independently confirmed that an older device is present.
    public static func legacyAfterStatusReadback() -> FirmwareCapabilityProfile {
        FirmwareCapabilityProfile(identity: .legacy)
    }

    // These flags permit read-only probes. A matching catalog key alone does
    // not prove the build SHA or authorize writes; each editor must also have
    // a successful device readback for the setting it changes.
    public var mayQueryOrdinaryKeys: Bool { identity == .knownWS2Catalog }
    public var mayQueryVoiceOnboarding: Bool { identity == .knownWS2Catalog }
    public var mayQuerySideSwitchBindings: Bool { identity == .knownWS2Catalog }
    public var mayQueryStandby: Bool { identity == .knownWS2Catalog }
    public var canWriteWithoutReadback: Bool { false }
    public var canUseWS3Presentation: Bool { false }
    public var canWriteWS3Resources: Bool { false }
}
