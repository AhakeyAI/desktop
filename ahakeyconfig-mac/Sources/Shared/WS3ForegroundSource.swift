import Foundation
import AppKit
import CoreFoundation
import Darwin

public struct WS3ProcessInstance: Equatable, Sendable {
    public let pid: Int32
    public let seconds: UInt64
    public let microseconds: UInt64
    public init?(pid: Int32, seconds: UInt64, microseconds: UInt64) {
        guard pid > 1, seconds > 0, microseconds < 1_000_000 else { return nil }
        self.pid = pid; self.seconds = seconds; self.microseconds = microseconds
    }
    public static func capture(_ pid: Int32) -> Self? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == geteuid(),
              info.pbi_flags & UInt32(PROC_FLAG_INEXIT) == 0 else { return nil }
        return Self(pid: pid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }
    public var isAlive: Bool { Self.capture(pid) == self }
}

public struct WS3ForegroundContext: Equatable, Sendable {
    public let generation: UInt64
    public let presentation: UInt64
    public init(generation: UInt64, presentation: UInt64) { self.generation = generation; self.presentation = presentation }
}

/// Numeric local IPC only. No window titles, command text, or session contents.
public struct WS3ForegroundUpdate: Equatable, Sendable {
    public struct Focus: Equatable, Sendable {
        public let application: WS3ProcessInstance
        public let terminal: WS3TerminalTaskIdentity
        public init(application: WS3ProcessInstance, terminal: WS3TerminalTaskIdentity) {
            self.application = application; self.terminal = terminal
        }
    }
    public let origin: WS3ProcessInstance
    public let sequence: UInt64
    public let context: WS3ForegroundContext
    public let focus: Focus?
    public init(origin: WS3ProcessInstance, sequence: UInt64, context: WS3ForegroundContext, focus: Focus?) {
        self.origin = origin; self.sequence = sequence; self.context = context; self.focus = focus
    }
    public var parameters: [String: Int]? {
        let values: [String: UInt64] = ["originPID": UInt64(origin.pid), "originSeconds": origin.seconds,
            "originMicros": origin.microseconds, "sequence": sequence, "generation": context.generation,
            "presentation": context.presentation, "focused": focus == nil ? 0 : 1]
        guard values.values.allSatisfy({ $0 <= Int.max }) else { return nil }
        var result = values.mapValues(Int.init)
        if let focus {
            let fields: [String: UInt64] = ["appPID": UInt64(focus.application.pid), "appSeconds": focus.application.seconds,
                "appMicros": focus.application.microseconds, "terminalDevice": UInt64(focus.terminal.device),
                "terminalGroup": UInt64(focus.terminal.processGroup), "terminalLeaderSeconds": focus.terminal.leaderStartedSeconds,
                "terminalLeaderMicros": focus.terminal.leaderStartedMicroseconds]
            guard fields.values.allSatisfy({ $0 <= Int.max }) else { return nil }
            result.merge(fields.mapValues(Int.init), uniquingKeysWith: { _, new in new })
        }
        return result
    }
    public init?(parameters body: [String: Any]) {
        func integer(_ key: String) -> Int? {
            guard let value = body[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return Int(value.stringValue)
        }
        func process(_ prefix: String) -> WS3ProcessInstance? {
            guard let pid = integer(prefix + "PID"), pid > 1, pid <= Int32.max,
                  let seconds = integer(prefix + "Seconds"), seconds > 0,
                  let micros = integer(prefix + "Micros"), micros >= 0 else { return nil }
            return WS3ProcessInstance(pid: Int32(pid), seconds: UInt64(seconds), microseconds: UInt64(micros))
        }
        guard let origin = process("origin"), let sequence = integer("sequence"), sequence > 0,
              let generation = integer("generation"), generation >= 0, let presentation = integer("presentation"), presentation >= 0,
              let focused = integer("focused"), (0...1).contains(focused) else { return nil }
        let focus: Focus?
        if focused == 1 {
            guard let app = process("app"), let device = integer("terminalDevice"), device >= 0, device <= UInt32.max,
                  let group = integer("terminalGroup"), group > 1, group <= Int32.max,
                  let seconds = integer("terminalLeaderSeconds"), seconds > 0,
                  let micros = integer("terminalLeaderMicros"), micros >= 0,
                  let terminal = WS3TerminalTaskIdentity(device: UInt32(device), processGroup: Int32(group),
                    leaderStartedSeconds: UInt64(seconds), leaderStartedMicroseconds: UInt64(micros)) else { return nil }
            focus = Focus(application: app, terminal: terminal)
        } else { focus = nil }
        self.init(origin: origin, sequence: UInt64(sequence), context: .init(generation: UInt64(generation), presentation: UInt64(presentation)), focus: focus)
    }
}

/// Main-queue owner shared by App and Agent. Native validation and process exit
/// notifications revoke priority without modifying task timestamps or approvals.
public final class WS3ForegroundReceiver {
    public static let refreshNotification = Notification.Name("lab.jawa.ahakeyconfig.presentation-foreground-refresh")
    private let context: () -> WS3ForegroundContext?
    private let apply: (WS3TerminalTaskIdentity?) -> Void
    private let originIsValid: (WS3ProcessInstance) -> Bool
    private let focusIsValid: (WS3ForegroundUpdate.Focus) -> Bool
    private let observeSystem: Bool
    private var latest: WS3ForegroundUpdate?
    private var activeFocus: WS3ForegroundUpdate.Focus?
    private var watchers: [DispatchSourceProcess] = []
    private var watchID = UUID()
    private var workspaceObservers: [NSObjectProtocol] = []

    public init(context: @escaping () -> WS3ForegroundContext?, apply: @escaping (WS3TerminalTaskIdentity?) -> Void,
        observeSystem: Bool = true,
        originIsValid: @escaping (WS3ProcessInstance) -> Bool = { $0.isAlive && NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier == "lab.jawa.ahakeyconfig" },
        focusIsValid: @escaping (WS3ForegroundUpdate.Focus) -> Bool = { focus in
            guard focus.application.isAlive, focus.terminal.isAlive(),
                  let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == focus.application.pid else { return false }
            return ["com.apple.Terminal", "com.googlecode.iterm2"].contains(app.bundleIdentifier ?? "")
        }) {
        self.context = context; self.apply = apply; self.observeSystem = observeSystem
        self.originIsValid = originIsValid; self.focusIsValid = focusIsValid
        if observeSystem {
            let center = NSWorkspace.shared.notificationCenter
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.revalidate() })
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.reset() })
        }
    }
    deinit {
        watchers.forEach { $0.cancel() }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    @discardableResult
    public func receive(_ update: WS3ForegroundUpdate) -> Bool {
        guard update.sequence > 0, context() == update.context, originIsValid(update.origin) else { return false }
        if let latest, latest.context == update.context {
            if latest.origin == update.origin {
                guard update.sequence > latest.sequence else { return false }
            } else if originIsValid(latest.origin) { return false }
        }
        latest = update
        activeFocus = update.focus.flatMap { focusIsValid($0) ? $0 : nil }
        installWatches()
        apply(activeFocus?.terminal)
        return true
    }
    public func revalidate() {
        guard let latest else { return }
        guard context() == latest.context, originIsValid(latest.origin) else { reset(); return }
        if let activeFocus, !focusIsValid(activeFocus) { revokeFocus() }
    }
    public func reset() {
        latest = nil; activeFocus = nil
        watchID = UUID(); watchers.forEach { $0.cancel() }; watchers.removeAll()
        apply(nil)
    }
    private func revokeFocus() {
        activeFocus = nil; installWatches(); apply(nil)
    }
    private func installWatches() {
        watchID = UUID(); watchers.forEach { $0.cancel() }; watchers.removeAll()
        guard observeSystem, let latest else { return }
        let id = watchID
        var pids: [(Int32, Bool)] = [(latest.origin.pid, true)]
        if let activeFocus { pids += [(activeFocus.application.pid, false), (activeFocus.terminal.processGroup, false)] }
        for (pid, isOrigin) in pids {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setRegistrationHandler { [weak self] in if self?.watchID == id { self?.revalidate() } }
            source.setEventHandler { [weak self] in
                guard let self, self.watchID == id else { return }
                if isOrigin { self.reset() } else { self.revokeFocus() }
            }
            watchers.append(source); source.resume()
        }
    }
}
