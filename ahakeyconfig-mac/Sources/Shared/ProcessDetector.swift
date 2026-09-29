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

    /// 一次检测结果的可发布投影（纯值类型，供去重决策与单元测试）。
    public struct DetectionSnapshot: Equatable {
        public var runningTargets: [Target]
        public var isAnyTargetRunning: Bool

        public init(runningTargets: [Target], isAnyTargetRunning: Bool) {
            self.runningTargets = runningTargets
            self.isAnyTargetRunning = isAnyTargetRunning
        }
    }

    @Published public private(set) var runningTargets: [Target] = []
    @Published public private(set) var isAnyTargetRunning: Bool = false

    public var targets: [Target] = ProcessDetector.defaultTargets()

    private var pollTimer: DispatchSourceTimer?
    private let pollInterval: TimeInterval
    private let queue = DispatchQueue(label: "lab.jawa.ahakeyconfig.processdetector")
    private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "ProcessDetector")

    /// GUI 侧（bundle ID / 应用名）最近一次判定为活跃的目标名集合。
    /// 由 NSWorkspace 启动/退出通知驱动重估，不随定时器每轮全量刷新。
    private var guiActiveNames: Set<String> = []
    /// CLI 侧（进程名 + 命令行提示）最近一次 ps 快照判定为活跃的目标名集合。
    private var cliActiveNames: Set<String> = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private static let processNameRegex = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9_.\\-]+$",
        options: []
    )
    private static let psURL = URL(fileURLWithPath: "/bin/ps")

    private struct RunningCLIProcess: Sendable {
        let executableName: String
        let commandLine: String
    }

    public init(pollInterval: TimeInterval = 5.0) {
        self.pollInterval = pollInterval
    }

    /// GUI（主 App）共享实例：15s CLI 轮询 + NSWorkspace 事件驱动的 GUI 检测。
    /// 应用级持有（App 启动即 start，退出才停），不再依赖任何窗口的 onAppear/onDisappear。
    public static let shared = ProcessDetector(pollInterval: 15.0)

    deinit {
        // Synchronous cancel avoids leaking the active dispatch source.
        queue.sync { cancelTimerOnQueue() }
    }

    public func start() {
        registerWorkspaceObservers()
        reevaluateGUITargets()
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelTimerOnQueue()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            // Run once below, then continue at the configured cadence. Scheduling at
            // `.now()` as well caused two overlapping process scans on every start.
            timer.schedule(deadline: .now() + self.pollInterval, repeating: self.pollInterval)
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for observer in self.workspaceObservers {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            self.workspaceObservers.removeAll()
        }
    }

    /// GUI 应用启动/退出即触发重估，检测延迟从「下一个轮询周期」降到事件到达。
    private func registerWorkspaceObservers() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workspaceObservers.isEmpty else { return }
            let center = NSWorkspace.shared.notificationCenter
            let names: [Notification.Name] = [
                NSWorkspace.didLaunchApplicationNotification,
                NSWorkspace.didTerminateApplicationNotification,
            ]
            for name in names {
                let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.reevaluateGUITargets()
                }
                self.workspaceObservers.append(observer)
            }
        }
    }

    private func cancelTimerOnQueue() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// 定时器轮询入口：每轮只做 CLI 检测（一次全量 ps 快照）。
    /// GUI 检测由 NSWorkspace 通知驱动（见 `reevaluateGUITargets`），不在此重复。
    public func checkNow() {
        // Snapshot mutable configuration on the main thread, then move the
        // heavy process lookups to a utility queue. This keeps the serial
        // timer queue responsive and avoids races with UI mutations.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let targetsSnapshot = self.targets

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                // Capture all command lines once. The old implementation launched pgrep for
                // every configured process name and then ps again for every matching PID.
                let cliProcesses = self.runningCLIProcesses()
                let active = Set(
                    targetsSnapshot
                        .filter { $0.isEnabled && self.isCLITargetRunning($0, cliProcesses: cliProcesses) }
                        .map { $0.name }
                )

                DispatchQueue.main.async {
                    self.cliActiveNames = active
                    self.publishCombinedOnMain()
                }
            }
        }
    }

    /// 重估 GUI 目标（bundle ID / 应用名匹配）。NSWorkspace 通知回调与 start() 初始评估走这里。
    private func reevaluateGUITargets() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let targetsSnapshot = self.targets
            let runningApps = NSWorkspace.shared.runningApplications
            let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })
            let runningNames = Set(runningApps.compactMap { $0.localizedName })
            self.guiActiveNames = Set(
                targetsSnapshot
                    .filter {
                        $0.isEnabled && self.isGUITargetRunning(
                            $0,
                            runningBundleIds: runningBundleIds,
                            runningNames: runningNames
                        )
                    }
                    .map { $0.name }
            )
            self.publishCombinedOnMain()
        }
    }

    /// 去重发布决策（纯函数，可测）：新旧结果相同返回 nil（零发布），否则返回应发布的新结果。
    public static func decidePublish(old: DetectionSnapshot, new: DetectionSnapshot) -> DetectionSnapshot? {
        new != old ? new : nil
    }

    /// 合并 GUI/CLI 两路缓存并按 decidePublish 去重发布：内容真实变化才赋值 @Published。
    private func publishCombinedOnMain() {
        let combined = targets.filter {
            $0.isEnabled && (guiActiveNames.contains($0.name) || cliActiveNames.contains($0.name))
        }
        let old = DetectionSnapshot(runningTargets: runningTargets, isAnyTargetRunning: isAnyTargetRunning)
        let new = DetectionSnapshot(runningTargets: combined, isAnyTargetRunning: !combined.isEmpty)
        guard let decided = Self.decidePublish(old: old, new: new) else { return }

        runningTargets = decided.runningTargets
        isAnyTargetRunning = decided.isAnyTargetRunning

        if decided.isAnyTargetRunning != old.isAnyTargetRunning {
            if decided.isAnyTargetRunning {
                let names = decided.runningTargets.map { $0.name }.joined(separator: ", ")
                log.info("Detected active AI tools: \(names)")
            } else {
                log.info("No active AI tools detected")
            }
        }
    }

    private func isGUITargetRunning(
        _ target: Target,
        runningBundleIds: Set<String>,
        runningNames: Set<String>
    ) -> Bool {
        if let bid = target.bundleIdentifier, runningBundleIds.contains(bid) {
            return true
        }
        return runningNames.contains(target.name)
    }

    private func isCLITargetRunning(
        _ target: Target,
        cliProcesses: [RunningCLIProcess]
    ) -> Bool {
        for processName in target.processNames {
            if isCLIProcessRunning(
                name: processName,
                hints: target.commandLineHints,
                processes: cliProcesses
            ) {
                return true
            }
        }
        return false
    }

    private func isCLIProcessRunning(
        name: String,
        hints: [String],
        processes: [RunningCLIProcess]
    ) -> Bool {
        guard validateProcessName(name) else {
            log.warning("Rejected unsafe process name: \(name)")
            return false
        }

        let matches = processes.lazy.filter { $0.executableName == name }
        if hints.isEmpty {
            return matches.first != nil
        }
        return matches.contains { process in
            hints.contains { process.commandLine.localizedCaseInsensitiveContains($0) }
        }
    }

    private func runningCLIProcesses() -> [RunningCLIProcess] {
        guard let result = runProcess(
            executable: Self.psURL,
            arguments: ["-axo", "command="]
        ), result.exitCode == 0 else {
            return []
        }

        return result.output.split(separator: "\n").compactMap { line in
            let commandLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let executable = commandLine.split(whereSeparator: \.isWhitespace).first else {
                return nil
            }
            let executableName = URL(fileURLWithPath: String(executable)).lastPathComponent
            guard !executableName.isEmpty else { return nil }
            return RunningCLIProcess(executableName: executableName, commandLine: commandLine)
        }
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
        } catch {
            return nil
        }
        // Drain stdout before waiting. `ps -axo command=` can exceed the pipe buffer;
        // waiting first deadlocks the child and lets subsequent timer scans pile up.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
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
