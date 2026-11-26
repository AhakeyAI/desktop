import AhaKeyConfigShared
import Darwin
import Foundation

enum StudioHookEntryInstaller {
    enum Failure: LocalizedError {
        case invalidEntry
        case timedOut
        case selfCheckFailed

        var errorDescription: String? {
            switch self {
            case .invalidEntry: return NSLocalizedString("找不到可执行的 Hook 程序。", comment: "")
            case .timedOut: return NSLocalizedString("Hook 入口自检超时。", comment: "")
            case .selfCheckFailed: return NSLocalizedString("Hook 入口自检失败，请确认安装的是完整的 Studio。", comment: "")
            }
        }
    }

    @discardableResult
    static func prepare(source: URL, destination: URL) throws -> CodexHookInstallation.EntryIdentity {
        let files = FileManager.default
        guard files.isExecutableFile(atPath: source.path) else { throw Failure.invalidEntry }
        let bin = destination.deletingLastPathComponent()
        try files.createDirectory(at: bin, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        if let identity = CodexHookInstallation.EntryIdentity(at: destination),
           files.contentsEqual(atPath: source.path, andPath: destination.path) {
            try selfCheck(destination)
            return identity
        }

        let stage = bin.appendingPathComponent(".ahakey-hook-\(UUID().uuidString)")
        defer { try? files.removeItem(at: stage) }
        try files.copyItem(at: source, to: stage)
        guard let identity = CodexHookInstallation.EntryIdentity(at: stage) else { throw Failure.invalidEntry }
        try selfCheck(stage)

        // The checked file is renamed within the same directory. Existing Hook invocations
        // keep their open executable and subsequent invocations see the new file.
        guard rename(stage.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return identity
    }

    private static func selfCheck(_ executable: URL) throws {
        let completed = DispatchSemaphore(value: 0)
        let output = Pipe()
        let process = Process()
        process.executableURL = executable
        // An older agent also treats this as a Hook subcommand and exits without starting BLE.
        process.arguments = ["hook", HookEntrySelfCheck.argument]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        guard completed.wait(timeout: .now() + .seconds(5)) == .success else {
            if process.isRunning { process.terminate() }
            throw Failure.timedOut
        }
        guard process.terminationStatus == 0,
              let report = try? JSONDecoder().decode(HookEntrySelfCheck.self, from: output.fileHandleForReading.readDataToEndOfFile()),
              report == .current else { throw Failure.selfCheckFailed }
    }
}
