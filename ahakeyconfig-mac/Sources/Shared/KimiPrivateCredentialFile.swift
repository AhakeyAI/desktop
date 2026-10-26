import Foundation
import Darwin

struct KimiLocalBearerCredential: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    fileprivate let token: String
    var description: String { "<redacted>" }
    var debugDescription: String { "<redacted>" }
    var customMirror: Mirror { Mirror(self, children: [] as [(label: String?, value: Any)]) }
    func withAuthorizationHeader<Value>(_ operation: (String) throws -> Value) rethrows -> Value {
        try operation("Bearer " + token)
    }
}

enum KimiPrivateCredentialFile {
    enum Failure: Error, Equatable { case notAuthorized, untrustedOwner, invalidFile, changed, invalidToken }
    // The caller must bind this path to the verified instance's trusted home and
    // recheck its process identity and listener in verifyOwner. This helper is not
    // a discovery API or a grant to manage sessions. No production caller yet.
    static func read(_ url: URL, userAuthorized: Bool,
                     verifyOwner: () -> Bool) throws -> KimiLocalBearerCredential {
        guard userAuthorized else { throw Failure.notAuthorized }
        guard verifyOwner() else { throw Failure.untrustedOwner }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.invalidFile }
        defer { close(fd) }
        var original = stat()
        guard fstat(fd, &original) == 0, valid(original) else { throw Failure.invalidFile }
        var bytes = [UInt8](repeating: 0, count: Int(original.st_size)), offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw Failure.changed }
            offset += count
        }
        var current = stat(), named = stat()
        guard fstat(fd, &current) == 0, lstat(url.path, &named) == 0, valid(current), valid(named),
              same(original, current), same(original, named), verifyOwner() else { throw Failure.changed }
        guard let raw = String(bytes: bytes, encoding: .utf8) else { throw Failure.invalidToken }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
        guard (32...512).contains(token.utf8.count), token.utf8.allSatisfy(allowed.contains) else { throw Failure.invalidToken }
        return KimiLocalBearerCredential(token: token)
    }
    private static func valid(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_uid == geteuid() && info.st_mode & 0o077 == 0 &&
            info.st_nlink == 1 && (32...1024).contains(info.st_size)
    }
    private static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
            a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
            a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}
