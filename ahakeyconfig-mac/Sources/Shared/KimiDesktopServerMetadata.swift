import Foundation
import CoreFoundation

/// Metadata proof for the inspected Desktop/server pairs, not a generic 2.x API.
/// This is neither a session owner proof nor authorization to change permissions.
struct KimiDesktopServerMetadata: Equatable {
    let serverID: String
    let serverVersion: String
    let startedAt: Int64

    static func parse(_ data: Data, expected: KimiDesktopInstanceDiscovery.Registration,
                      installedVersion: String) -> Self? {
        guard data.count <= 64 * 1024,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              integer(envelope["code"]) == 0,
              let body = envelope["data"] as? [String: Any],
              let id = body["server_id"] as? String, validAPIIdentity(id),
              let version = body["server_version"] as? String,
              let required = capabilityKeys(installedVersion: installedVersion, serverVersion: version),
              expected.serverVersion == nil || expected.serverVersion == version,
              let started = timestamp(body["started_at"]),
              // Registration precedes the HTTP app's Date().toISOString().
              // Bind the server ID/process separately; do not require identical clocks.
              started >= expected.startedMilliseconds,
              started - expected.startedMilliseconds <= 60_000,
              let bypass = body["dangerous_bypass_auth"] as? NSNumber,
              CFGetTypeID(bypass) == CFBooleanGetTypeID(), !bypass.boolValue,
              body["backend"] as? String == "v2",
              let capabilities = body["capabilities"] as? [String: Any],
              Set(capabilities.keys) == required,
              required.allSatisfy({ key in
                  guard let flag = capabilities[key] as? NSNumber else { return false }
                  return CFGetTypeID(flag) == CFBooleanGetTypeID() && flag.boolValue
              }) else { return nil }
        return Self(serverID: id, serverVersion: version, startedAt: started)
    }

    // 1.2.1 removed terminal from /meta. The permission bridge only uses the
    // independently inspected HTTP session endpoints in both contracts.
    private static func capabilityKeys(installedVersion: String, serverVersion: String) -> Set<String>? {
        let common: Set<String> = ["websocket", "file_upload", "fs_query", "mcp", "tasks"]
        switch (installedVersion, serverVersion) {
        case ("1.1.3", "2.3.2"): return common.union(["terminal"])
        case ("1.2.1", "2.4.0"): return common
        default: return nil
        }
    }

    // The HTTP app creates a different ULID from instanceRegistry.register().
    // Endpoint ownership is bound by the signed process/listener, not ID equality.
    private static func validAPIIdentity(_ value: String) -> Bool {
        let bytes = Array(value.utf8), alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
        return bytes.count == 26 && (UInt8(48)...55).contains(bytes[0]) && bytes.allSatisfy(alphabet.contains)
    }
    private static func timestamp(_ value: Any?) -> Int64? {
        guard let text = value as? String,
              text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#,
                         options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        let milliseconds = date.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds > 0, milliseconds <= 9_007_199_254_740_991 else { return nil }
        return Int64(milliseconds.rounded())
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, abs(number.doubleValue) <= 9_007_199_254_740_991,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
        return number.int64Value
    }
}
