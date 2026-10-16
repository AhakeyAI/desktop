import Foundation

/// Root boolean only; nested keys and multiline strings are not settings.
public enum KimiConfigPolicySync {
    public enum Outcome: Equatable { case unchanged, updated, missing, invalid, writeFailed, notOwned, disabled }
    public static var productionConfigURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi/config.toml") }
    static func leaseURL(_ url: URL) -> URL { url.appendingPathExtension("ahakey-auto-lease") }

    public static func apply(auto: Bool) -> Outcome {
        apply(auto: auto, configURL: productionConfigURL, controlDirectory: ApprovalAutomationControl.productionDirectory)
    }
    static func apply(auto: Bool, configURL: URL, controlDirectory: URL) -> Outcome {
        ApprovalAutomationControl.locked(directory: controlDirectory) {
            if auto && !ApprovalAutomationControl.enabledUnlocked(.kimi, directory: controlDirectory) { return .disabled }
            return update(auto: auto, configURL: configURL)
        } ?? .writeFailed
    }
    struct Value { let range: Range<Int>; let enabled: Bool; let legacyOwned: Bool }
    static func locate(_ text: String) throws -> (Value?, Int) {
        let bytes = Array(text.utf8)
        let statements = try TomlPolicyLocator.statements(in: text)
        var root = true, found: Value?, insertion = bytes.count
        for statement in statements {
            switch statement.kind {
            case .table(let path, _):
                if path.first == "default_yolo" { throw ParseFailure.invalid }
                if root { insertion = statement.range.lowerBound }; root = false
            case .assignment(let path) where root && path.first == "default_yolo" && path.count != 1:
                throw ParseFailure.invalid
            case .assignment(let path) where root && path == ["default_yolo"]:
                guard found == nil, let equal = bytes[statement.range].firstIndex(of: 0x3D) else { throw ParseFailure.invalid }
                var start = equal + 1
                while start < statement.range.upperBound && [9, 32].contains(bytes[start]) { start += 1 }
                var end = start
                while end < statement.range.upperBound && ![10, 13, 35].contains(bytes[end]) { end += 1 }
                var trimmedEnd = end
                while trimmedEnd > start && [9, 32].contains(bytes[trimmedEnd - 1]) { trimmedEnd -= 1 }
                let token = String(decoding: bytes[start..<trimmedEnd], as: UTF8.self)
                guard token == "true" || token == "false" else { throw ParseFailure.invalid }
                let comment = String(decoding: bytes[end..<statement.range.upperBound], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                found = Value(range: start..<trimmedEnd, enabled: token == "true", legacyOwned: comment.hasPrefix("# AhaKey: dial auto;"))
            default: break
            }
        }
        return (found, insertion)
    }
    enum ParseFailure: Error { case invalid }
    private static func update(auto: Bool, configURL: URL) -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: configURL), let text = String(data: data, encoding: .utf8),
              let (value, insertion) = try? locate(text) else { return .invalid }
        if value?.enabled == auto {
            if !auto { try? fm.removeItem(at: leaseURL(configURL)) }
            return .unchanged
        }
        if auto {
            do { try Data([1]).write(to: leaseURL(configURL), options: .atomic) } catch { return .writeFailed }
        }
        var bytes = Array(data)
        if let value { bytes.replaceSubrange(value.range, with: Array((auto ? "true" : "false").utf8)) }
        else {
            let newline = text.contains("\r\n") ? "\r\n" : (text.contains("\r") ? "\r" : "\n")
            let before = insertion > 0 && ![10,13].contains(bytes[insertion - 1]) ? newline : ""
            bytes.insert(contentsOf: Array((before + "default_yolo = \(auto ? "true" : "false")" + newline).utf8), at: insertion)
        }
        do {
            try Data(bytes).write(to: configURL, options: .atomic)
            if !auto { try? fm.removeItem(at: leaseURL(configURL)) }
            return .updated
        } catch { return .writeFailed }
    }
    static func releaseOwnedAutomation(configURL: URL) -> Outcome {
        guard let data = try? Data(contentsOf: configURL), let text = String(data: data, encoding: .utf8) else {
            return FileManager.default.fileExists(atPath: configURL.path) ? .invalid : .missing
        }
        guard let (value, _) = try? locate(text) else { return .invalid }
        guard FileManager.default.fileExists(atPath: leaseURL(configURL).path) || value?.legacyOwned == true else { return .notOwned }
        if value?.enabled == true { return update(auto: false, configURL: configURL) }
        try? FileManager.default.removeItem(at: leaseURL(configURL))
        return .unchanged
    }
}
