import Foundation

/// Preflight and actual send use the same mailbox gate. A command that cannot
/// be sent must fail before installing a response continuation, not time out.
public enum WS3CommandOwnership {
    public static func negotiatedGrant(for data: Data) -> ConfigurationCommandPolicy.ConfirmedWrite? {
        guard ACR4Command(request: data) != nil || CompactResourceCommand(request: data) != nil else { return nil }
        return .negotiatedResource
    }
    public static func permits(_ data: Data, uploading: Bool, updating: Bool,
                               grant: ConfigurationCommandPolicy.ConfirmedWrite) -> Bool {
        guard uploading || updating else { return true }
        let ownsWrite = uploading ? (grant == .ws3Resource || grant == .negotiatedResource) :
            (grant == .ws3Display || grant == .ws3ResourceRestore)
        return ownsWrite || (data.count > 2 && [UInt8(0x00), 0x88].contains(data[2]))
    }
}
