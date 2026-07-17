import Foundation

/// File-based diagnostic logger for sleep protection events.
public enum PowerProtectionDiagnosticLogger {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static var logFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics", isDirectory: true)
            .appendingPathComponent("power-protection.log")
    }

    public static func log(event: String, details: [String: Any] = [:]) {
        let dir = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var payload: [String: Any] = [
            "ts": dateFormatter.string(from: Date()),
            "event": event,
        ]
        for (k, v) in details { payload[k] = v }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        appendLine(line)
    }

    private static func appendLine(_ line: String) {
        guard let out = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? out.write(to: logFileURL, options: .atomic)
            return
        }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(out)
        }
    }

    public static func readRecentLogs(maxBytes: Int = 50_000) -> String {
        guard let data = try? Data(contentsOf: logFileURL) else { return "" }
        if data.count <= maxBytes {
            return String(data: data, encoding: .utf8) ?? ""
        }
        let tail = data.suffix(maxBytes)
        return String(data: tail, encoding: .utf8) ?? ""
    }
}
