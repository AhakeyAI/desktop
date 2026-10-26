import Foundation
import CoreFoundation

/// Metadata proof for the statically inspected Code Desktop 1.1.3 / server 2.3.2.
/// This is neither a session owner proof nor authorization to change permissions.
struct KimiDesktopServerMetadata: Equatable {
    let serverID: String
    let serverVersion: String
    let startedAt: Int64

    static func parse(_ data: Data, expected: KimiDesktopInstanceDiscovery.Registration) -> Self? {
        guard data.count <= 64 * 1024,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              integer(envelope["code"]) == 0,
              let body = envelope["data"] as? [String: Any],
              let id = body["server_id"] as? String, id == expected.serverID,
              let version = body["server_version"] as? String, version == "2.3.2",
              expected.serverVersion == nil || expected.serverVersion == version,
              let started = integer(body["started_at"]), started == expected.startedMilliseconds,
              let bypass = body["dangerous_bypass_auth"] as? NSNumber,
              CFGetTypeID(bypass) == CFBooleanGetTypeID(), !bypass.boolValue,
              body["backend"] as? String == "v2",
              let capabilities = body["capabilities"] as? [String: Any],
              ["websocket", "file_upload", "fs_query", "mcp", "tasks", "terminal"].allSatisfy({ key in
                  guard let flag = capabilities[key] as? NSNumber else { return false }
                  return CFGetTypeID(flag) == CFBooleanGetTypeID() && flag.boolValue
              }) else { return nil }
        return Self(serverID: id, serverVersion: version, startedAt: started)
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, abs(number.doubleValue) <= 9_007_199_254_740_991,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
        return number.int64Value
    }
}
