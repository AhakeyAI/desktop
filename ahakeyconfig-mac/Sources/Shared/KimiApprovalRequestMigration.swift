import Foundation

/// Upgrade only the AhaKey-owned socket loader, leaving other SDK requests intact.
public enum KimiApprovalRequestMigration {
    public static func upgradeOwnedHelper(in source: String) -> String {
        guard source.contains("_AHAKEY_SOCKET_PATH = \"/tmp/ahakey.sock\""),
              let start = source.range(of: "def _load_ahakey_override_uncached() -> dict[str, object] | None:"),
              let end = source.range(of: "\ndef get_ahakey_approval_override(", range: start.upperBound..<source.endIndex)
        else { return source }
        let helperRange = start.lowerBound..<end.lowerBound
        let helper = source[helperRange].replacingOccurrences(
            of: #"sock.sendall(b'{"cmd":"approval_status"}\n')"#,
            with: #"sock.sendall(b'{"cmd":"kimi_approval_status"}\n')"#)
        return source.replacingCharacters(in: helperRange, with: helper)
    }
}
