import AppKit
import Combine
import Foundation
import os.log

/// Detects running AI coding tools by bundle ID (GUI) or process name + args (CLI).
public final class ProcessDetector: ObservableObject {

    /// A target that can trigger sleep protection.
    public struct Target: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public var name: String
        public var bundleIdentifier: String?
        public var processNames: [String]
        /// Extra command-line substrings used to disambiguate wrapper processes.
        public var commandLineHints: [String]
        public var isEnabled: Bool

        public init(
            name: String,
            bundleIdentifier: String? = nil,
            processNames: [String] = [],
            commandLineHints: [String] = [],
            isEnabled: Bool = true
        ) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.processNames = processNames
            self.commandLineHints = commandLineHints
            self.isEnabled = isEnabled
        }
    }

    @Published public private(set) var runningTargets: [Target] = []
    @Published public private(set) var isAnyTargetRunning: Bool = false

    public var targets: [Target] = ProcessDetector.defaultTargets()

    private var pollTimer: DispatchSourceTimer?
    private let pollInterval: TimeInterval
    private let queue = DispatchQueue(label: "lab.jawa.ahakeyconfig.processdetector")
    private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "ProcessDetector")

    private static let processNameRegex = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9_.\\-]+$",
        options: []
    )
    private static let pgrepURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    private static let psURL = URL(fileURLWithPath: "/bin/ps")

    public init(pollInterval: TimeInterval = 5.0) {
        self.pollInterval = pollInterval
    }

    deinit {
        // Synchronous cancel avoids leaking the active dispatch source.
        queue.sync { cancelTimerOnQueue() }
    }

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelTimerOnQueue()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.pollInterval)
            timer.setEventHandler { [weak self] in
                self?.checkNow()
            }
            timer.resume()
            self.pollTimer = timer

            self.checkNow()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.cancelTimerOnQueue()
        }
    }

    private func cancelTimerOnQueue() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    public func checkNow() {
        // Snapshot mutable configuration on the main thread, then move the
        // heavy process lookups to a utility queue. This keeps the serial
        // timer queue responsive and avoids races with UI mutations.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let targetsSnapshot = self.targets
            let runningApps = NSWorkspace.shared.runningApplications

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let active = self.detect(
                    targets: targetsSnapshot,
                    runningApps: runningApps
                )

                DispatchQueue.main.async {
                    let wasRunning = self.isAnyTargetRunning
                    self.runningTargets = active
                    self.isAnyTargetRunning = !active.isEmpty

                    if self.isAnyTargetRunning != wasRunning {
                        if self.isAnyTargetRunning {
                            let names = active.map { $0.name }.joined(separator: ", ")
                            self.log.info("Detected active AI tools: \(names)")
                        } else {
                            self.log.info("No active AI tools detected")
                        }
                    }
                }
            }
        }
    }

    private func detect(
        targets: [Target],
        runningApps: [NSRunningApplication]
    ) -> [Target] {
        let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })
        let runningNames = Set(runningApps.compactMap { $0.localizedName })

        var active: [Target] = []
        for target in targets where target.isEnabled {
            if isTargetRunning(
                target,
                runningBundleIds: runningBundleIds,
                runningNames: runningNames
            ) {
                active.append(target)
            }
        }
        return active
    }

    private func isTargetRunning(
        _ target: Target,
        runningBundleIds: Set<String>,
        runningNames: Set<String>
    ) -> Bool {
        if let bid = target.bundleIdentifier, runningBundleIds.contains(bid) {
            return true
        }
        if runningNames.contains(target.name) {
            return true
        }

        for processName in target.processNames {
            if isCLIProcessRunning(name: processName, hints: target.commandLineHints) {
                return true
            }
        }
        return false
    }

    private func isCLIProcessRunning(name: String, hints: [String]) -> Bool {
        guard validateProcessName(name) else {
            log.warning("Rejected unsafe process name: \(name)")
            return false
        }

        let (pgrepOutput, _) = runProcess(
            executable: Self.pgrepURL,
            arguments: ["-x", name]
        ) ?? ("", -1)

        let pids = pgrepOutput
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .filter { UInt32($0) != nil }

        guard !pids.isEmpty else { return false }
        if hints.isEmpty { return true }

        for pid in pids {
            guard validateProcessName(pid) else { continue }
            let (cmdline, _) = runProcess(
                executable: Self.psURL,
                arguments: ["-o", "command=", "-p", pid]
            ) ?? ("", -1)
            for hint in hints where cmdline.contains(hint) {
                return true
            }
        }
        return false
    }

    private func validateProcessName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return Self.processNameRegex.firstMatch(in: name, options: [], range: range) != nil
    }

    private func runProcess(executable: URL, arguments: [String]) -> (output: String, exitCode: Int32)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }

    /// Default targets aligned with AhaKey's IDE hook support.
    public static func defaultTargets() -> [Target] {
        [
            Target(
                name: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                processNames: ["Cursor"]
            ),
            Target(
                name: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                processNames: ["Code"]
            ),
            Target(
                name: "Codex",
                bundleIdentifier: "com.openai.codex",
                processNames: ["codex", "openai-codex", "node", "python3"],
                commandLineHints: ["codex", "openai-codex"]
            ),
            Target(
                name: "Claude Code",
                processNames: ["claude", "claude-code", "node", "python3"],
                commandLineHints: ["claude", "claude-code"]
            ),
            Target(
                name: "Kimi Code",
                processNames: ["kimi", "kimi-cli", "python3", "Python"],
                commandLineHints: ["kimi", "kimi-cli"]
            ),
        ]
    }
}
