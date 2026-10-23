import Foundation
import CoreFoundation

/// Optional host-side target proof. Old callers omit both fields; the screen
/// editor supplies both after a fresh read, including after an artwork lease.
public enum WS3PresentationRequestTarget {
    public static func matches(_ request: [String: Any], deviceID: UUID?, generation: UInt64) -> Bool {
        guard request["deviceID"] != nil || request["generation"] != nil else { return true }
        guard let rawID = request["deviceID"] as? String, let expectedID = UUID(uuidString: rawID),
              expectedID == deviceID,
              let number = request["generation"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let expectedGeneration = UInt64(number.stringValue) else { return false }
        return expectedGeneration == generation
    }
}
