import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps
import AhaKeyVirtualDisplayBridge
import os.log
import SwiftUI
import Darwin

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "PowerProtection")

// MARK: - Protection Level

/// Represents the layers of sleep prevention available on the current system.
public enum PowerProtectionLevel: Int, CaseIterable, Comparable, CustomStringConvertible, Sendable {
    /// L1: `IOPMAssertionCreateWithName` preventing idle system sleep.
    case assertion = 1
    /// L2: `IORegistry` sleep-disabled hint.
    case ioRegistry = 2
    /// L3: Virtual display forcing clamshell mode (macOS 14+).
    case virtualDisplay = 3

    public static func < (lhs: PowerProtectionLevel, rhs: PowerProtectionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .assertion:      return NSLocalizedString("L1: 系统断言", comment: "")
        case .ioRegistry:     return NSLocalizedString("L2: IORegistry", comment: "")
        case .virtualDisplay: return NSLocalizedString("L3: 虚拟显示器", comment: "")
        }
    }
}

// MARK: - Protection Reason

/// Named reasons why the system should stay awake.
public struct PowerProtectionReason: Hashable, RawRepresentable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let aiCodingIdleHook    = PowerProtectionReason(rawValue: "aiCodingIdleHook")
    public static let aiCodingLidCloseHook = PowerProtectionReason(rawValue: "aiCodingLidCloseHook")
    public static let aiCodingIdleProcess = PowerProtectionReason(rawValue: "aiCodingIdleProcess")
    public static let aiCodingLidCloseProcess = PowerProtectionReason(rawValue: "aiCodingLidCloseProcess")
    public static let firmwareUpgrade     = PowerProtectionReason(rawValue: "firmwareUpgrade")
    public static let oledUpload          = PowerProtectionReason(rawValue: "oledUpload")
    public static let userRequestedIdle   = PowerProtectionReason(rawValue: "userRequestedIdle")
    public static let userRequestedLidClose = PowerProtectionReason(rawValue: "userRequestedLidClose")

    public var description: String { rawValue }

    /// The strongest level this reason requires.
    public var requiredLevel: PowerProtectionLevel {
        switch self {
        case .aiCodingIdleHook, .aiCodingIdleProcess:
            // WBS 5.4 Codex 15:07 裁决：L2（IORegistry SleepDisabled）非 root 不可写，
            // 不能作防空闲休眠承重层；idle 类 reason 提升为 L1 系统断言（pmset 可见）。
            return .assertion
        case .firmwareUpgrade, .oledUpload:
            return .ioRegistry
        case .aiCodingLidCloseHook, .aiCodingLidCloseProcess,
             .userRequestedLidClose:
            return .virtualDisplay
        case .userRequestedIdle:
            return .assertion
        default:
            return .assertion
        }
    }

    public var isLidCloseReason: Bool {
        self == .aiCodingLidCloseHook
        || self == .aiCodingLidCloseProcess
        || self == .userRequestedLidClose
    }

    public var displayName: String {
        switch self {
        case .aiCodingIdleHook, .aiCodingIdleProcess:
            return NSLocalizedString("编程中", comment: "")
        case .aiCodingLidCloseHook, .aiCodingLidCloseProcess:
            return NSLocalizedString("编程合盖保护", comment: "")
        case .firmwareUpgrade:
            return NSLocalizedString("固件升级中", comment: "")
        case .oledUpload:
            return NSLocalizedString("OLED 上传中", comment: "")
        case .userRequestedIdle:
            return NSLocalizedString("用户请求：阻止空闲休眠", comment: "")
        case .userRequestedLidClose:
            return NSLocalizedString("用户请求：合盖保护", comment: "")
        default:                return rawValue
        }
    }
}

// MARK: - Safety Settings

/// User-configurable safety thresholds for lid-close protection.
public struct PowerProtectionSafetySettings: Equatable, Sendable, Codable {
    /// Battery percentage below which L3 is disabled.
    public var l3DisableBatteryThreshold: Int
    /// Battery percentage below which all protection is released.
    public var fullReleaseBatteryThreshold: Int
    /// Thermal threshold (Celsius) above which L3 is disabled.
    public var thermalThresholdCelsius: Double
    /// Maximum duration of lid-close protection (seconds).
    public var maxLidCloseDuration: TimeInterval
    /// If true, ignore duration and battery limits (user explicitly opts in).
    public var alwaysAllow: Bool

    public init(
        l3DisableBatteryThreshold: Int = 20,
        fullReleaseBatteryThreshold: Int = 10,
        thermalThresholdCelsius: Double = 45.0,
        maxLidCloseDuration: TimeInterval = 7200,
        alwaysAllow: Bool = false
    ) {
        self.l3DisableBatteryThreshold = l3DisableBatteryThreshold
        self.fullReleaseBatteryThreshold = fullReleaseBatteryThreshold
        self.thermalThresholdCelsius = thermalThresholdCelsius
        self.maxLidCloseDuration = maxLidCloseDuration
        self.alwaysAllow = alwaysAllow
    }
}

// MARK: - Power Protection Manager

/// Central manager for keeping the system awake during critical operations.
///
/// Thread safety:
/// - All mutable state and IOKit/virtual-display operations live on a private serial queue.
/// - `@Published` properties are updated only on the main thread from queue snapshots.
/// - Public API is synchronous from the caller's perspective but dispatches work to the queue.
///
/// Features:
/// - Layered protection: L1 assertion, L2 IORegistry, L3 virtual display.
/// - Reason-based lifecycle: multiple concurrent reasons; protection stays alive
///   until the last reason ends.
/// - Safety guardrails: battery, thermal, and duration limits.
/// - macOS 12+ compatible; L3 virtual display uses private CGVirtualDisplay API
///   and is only available on macOS 14+ where the symbols are present.
public final class PowerProtectionManager: ObservableObject {

    /// Shared instance for the app process. The agent uses its own instance so
    /// protection survives independently of the GUI lifecycle.
    public static let shared = PowerProtectionManager()

    // MARK: - Published State (main thread only)

    @Published public private(set) var activeReasons: Set<PowerProtectionReason> = []
    @Published public private(set) var activeLevel: PowerProtectionLevel?
    @Published public private(set) var failedLayers: [PowerProtectionLevel: String] = [:]
    @Published public private(set) var isLidCloseProtectionAvailable: Bool = false
    @Published public private(set) var lastSafetyEvent: String?

    // MARK: - Safety

    @Published public var safetySettings = PowerProtectionSafetySettings() {
        didSet {
            saveSafetySettings()
            queue.async { [weak self] in self?.applyProtection() }
        }
    }

    /// If true, the user has enabled lid-close protection as a default behavior.
    @Published public var lidCloseProtectionEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(lidCloseProtectionEnabled, forKey: Self.lidCloseEnabledKey)
            queue.async { [weak self] in self?.applyProtection() }
        }
    }

    /// If false, the manager never activates any protection (global kill switch).
    @Published public var enabled: Bool = true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            applyUserRequestedReasons()
            queue.async { [weak self] in self?.applyProtection() }
        }
    }

    /// Set by the main app so user-requested reasons are only added in the GUI process,
    /// not in the background agent.
    public var isAppMode: Bool = false {
        didSet { applyUserRequestedReasons() }
    }

    // MARK: - Private State (queue only)

    private struct State {
        var activeReasons: Set<PowerProtectionReason> = []
        var activeLevel: PowerProtectionLevel?
        var failedLayers: [PowerProtectionLevel: String] = [:]
        var lastSafetyEvent: String?
        var lidCloseStartTime: Date?
    }

    private var state = State()
    private let queue = DispatchQueue(label: "lab.jawa.ahakeyconfig.powerprotection")
    private var safetyTimer: DispatchSourceTimer?

    private let assertion = AssertionProtection()
    private let ioRegistry = IORegistryProtection()
    private let virtualDisplay = VirtualDisplayProtection()

    private static let enabledKey = "lab.jawa.ahakeyconfig.powerProtection.enabled"
    private static let lidCloseEnabledKey = "lab.jawa.ahakeyconfig.powerProtection.lidCloseEnabled"
    private static let safetySettingsKey = "lab.jawa.ahakeyconfig.powerProtection.safety"

    // MARK: - Init

    public init() {
        isLidCloseProtectionAvailable = VirtualDisplayProtection.isAvailable
        let saved = Self.loadSavedSettings()
        enabled = saved.enabled
        lidCloseProtectionEnabled = saved.lidCloseEnabled
        safetySettings = saved.safetySettings
        // Always clean up any stale assertions from a previous crash on launch.
        queue.async { [weak self] in
            self?.assertion.deactivate()
            self?.ioRegistry.deactivate()
            self?.virtualDisplay.deactivate()
            self?.state = State()
            self?.publishSnapshot()
        }
        applyUserRequestedReasons()
        startSafetyTimer()
    }

    deinit {
        safetyTimer?.cancel()
        assertion.deactivate()
        ioRegistry.deactivate()
        virtualDisplay.deactivate()
    }

    // MARK: - Public API

    /// Begin protecting the system for the given reason.
    public func begin(_ reason: PowerProtectionReason) {
        guard enabled else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let inserted = self.state.activeReasons.insert(reason).inserted
            guard inserted else { return }
            log.info("Begin protection for reason: \(reason.rawValue)")
            PowerProtectionDiagnosticLogger.log(event: "begin", details: ["reason": reason.rawValue])
            self.applyProtection()
        }
    }

    /// End protection for the given reason.
    public func end(_ reason: PowerProtectionReason) {
        queue.async { [weak self] in
            guard let self else { return }
            let removed = self.state.activeReasons.remove(reason) != nil
            guard removed else { return }
            log.info("End protection for reason: \(reason.rawValue)")
            PowerProtectionDiagnosticLogger.log(event: "end", details: ["reason": reason.rawValue])
            self.applyProtection()
        }
    }

    /// Immediately release all protection layers and clear all reasons.
    @discardableResult
    public func deactivateAll() -> Bool {
        queue.sync { [weak self] in
            guard let self else { return false }
            self.state.activeReasons.removeAll()
            self.assertion.deactivate()
            self.ioRegistry.deactivate()
            self.virtualDisplay.deactivate()
            self.state.activeLevel = nil
            self.state.failedLayers.removeAll()
            self.state.lidCloseStartTime = nil
            log.info("All protection deactivated.")
            PowerProtectionDiagnosticLogger.log(event: "deactivate_all")
            self.publishSnapshot()
            return true
        }
    }

    /// Called once by the main app to indicate this instance lives in the GUI process.
    public func configureAsApp() {
        isAppMode = true
    }

    private func applyUserRequestedReasons() {
        guard isAppMode else {
            end(.userRequestedIdle)
            end(.userRequestedLidClose)
            return
        }
        if enabled {
            begin(.userRequestedIdle)
            begin(.userRequestedLidClose)
        } else {
            end(.userRequestedIdle)
            end(.userRequestedLidClose)
        }
    }

    /// Returns true if any protection is currently active.
    public var isProtectionActive: Bool {
        queue.sync { state.activeLevel != nil }
    }

    /// Returns a human-readable status summary.
    public var statusSummary: String {
        queue.sync {
            guard let level = state.activeLevel else { return NSLocalizedString("未激活", comment: "") }
            let reasons = state.activeReasons.map { $0.displayName }.sorted().joined(separator: ", ")
            return "\(level.description) · \(NSLocalizedString("原因：", comment: ""))\(reasons)"
        }
    }

    // MARK: - Internal Logic (queue only)

    private func applyProtection() {
        let targetLevel = computeTargetLevel()

        // Reset lid-close duration tracking whenever there is no active lid-close reason.
        if targetLevel == nil || !state.activeReasons.contains(where: \.isLidCloseReason) {
            state.lidCloseStartTime = nil
        }

        guard let target = targetLevel else {
            assertion.deactivate()
            ioRegistry.deactivate()
            virtualDisplay.deactivate()
            state.activeLevel = nil
            state.activeReasons.removeAll()
            state.failedLayers.removeAll()
            publishSnapshot()
            return
        }

        // Activate layers from lowest to highest.
        for level in PowerProtectionLevel.allCases where level <= target {
            activateLayer(level)
        }

        // Deactivate layers above target in reverse order.
        for level in PowerProtectionLevel.allCases.reversed() where level > target {
            deactivateLayer(level)
        }

        state.activeLevel = target
        log.info("Protection applied at level: \(target.rawValue)")
        PowerProtectionDiagnosticLogger.log(
            event: "apply",
            details: [
                "level": target.rawValue,
                "levelName": target.description,
                "reasons": Array(state.activeReasons.map { $0.rawValue }),
            ]
        )
        publishSnapshot()
    }

    private func computeTargetLevel() -> PowerProtectionLevel? {
        guard !state.activeReasons.isEmpty else { return nil }

        let wantsLidClose = state.activeReasons.contains(where: \.isLidCloseReason)
                            && lidCloseProtectionEnabled
        var maxLevel = PowerProtectionLevel.assertion

        for reason in state.activeReasons {
            if reason.isLidCloseReason && !wantsLidClose {
                maxLevel = max(maxLevel, .ioRegistry)
                continue
            }
            maxLevel = max(maxLevel, reason.requiredLevel)
        }

        // Full release on very low battery.
        if shouldReleaseAllDueToSafety() {
            state.activeReasons.removeAll()
            state.lastSafetyEvent = NSLocalizedString("电量过低，已完全释放合盖运行", comment: "")
            PowerProtectionDiagnosticLogger.log(event: "safety_full_release", details: ["battery": currentBatteryPercentage()])
            publishSnapshot()
            return nil
        }

        // Cap lid-close on battery/temperature.
        if shouldDisableLidCloseDueToSafety() {
            maxLevel = min(maxLevel, .ioRegistry)
            if maxLevel <= .ioRegistry {
                state.lastSafetyEvent = NSLocalizedString("安全阈值触发：已降级合盖运行", comment: "")
            }
        }

        if maxLevel == .virtualDisplay && !isLidCloseProtectionAvailable {
            maxLevel = .ioRegistry
        }

        return maxLevel
    }

    private func activateLayer(_ level: PowerProtectionLevel) {
        do {
            switch level {
            case .assertion:
                try assertion.activate()
            case .ioRegistry:
                try ioRegistry.activate()
            case .virtualDisplay:
                try virtualDisplay.activate()
            }
            state.failedLayers.removeValue(forKey: level)
        } catch {
            state.failedLayers[level] = error.localizedDescription
            log.error("Failed to activate \(level.description): \(error.localizedDescription)")
        }
    }

    private func deactivateLayer(_ level: PowerProtectionLevel) {
        switch level {
        case .assertion:    assertion.deactivate()
        case .ioRegistry:   ioRegistry.deactivate()
        case .virtualDisplay: virtualDisplay.deactivate()
        }
    }

    private func publishSnapshot() {
        let snapshot = state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeReasons = snapshot.activeReasons
            self.activeLevel = snapshot.activeLevel
            self.failedLayers = snapshot.failedLayers
            self.lastSafetyEvent = snapshot.lastSafetyEvent
        }
    }

    // MARK: - Safety Monitoring

    private func startSafetyTimer() {
        safetyTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10.0, repeating: 10.0)
        timer.setEventHandler { [weak self] in
            self?.performSafetyCheck()
        }
        timer.resume()
        safetyTimer = timer
    }

    internal func performSafetyCheck() {
        let hadLidClose = state.activeReasons.contains(where: \.isLidCloseReason)

        if shouldReleaseAllDueToSafety() {
            applyProtection()
            return
        }

        let shouldDowngrade = shouldDisableLidCloseDueToSafety()
        if shouldDowngrade && hadLidClose {
            applyProtection()
        }

        // Track lid-close duration unless the user has opted out of all limits.
        if hadLidClose && !safetySettings.alwaysAllow {
            let justStarted = state.lidCloseStartTime == nil
            if justStarted {
                state.lidCloseStartTime = Date()
                PowerProtectionDiagnosticLogger.log(
                    event: "lid_close_timer_start",
                    details: ["maxDuration": safetySettings.maxLidCloseDuration]
                )
            }
            if !justStarted,
               let start = state.lidCloseStartTime,
               Date().timeIntervalSince(start) >= safetySettings.maxLidCloseDuration {
                for reason in state.activeReasons where reason.isLidCloseReason {
                    state.activeReasons.remove(reason)
                }
                state.lastSafetyEvent = NSLocalizedString("达到最大合盖保护时长，已自动释放 L3", comment: "")
                state.lidCloseStartTime = nil
                PowerProtectionDiagnosticLogger.log(
                    event: "safety_timeout",
                    details: ["maxDuration": safetySettings.maxLidCloseDuration]
                )
                applyProtection()
            }
        } else {
            state.lidCloseStartTime = nil
        }

        // Heal: if protection is supposed to be active, refresh L2/L3 layers
        // in case another process (e.g. AhaKey Studio) deactivated them.
        if !state.activeReasons.isEmpty {
            ioRegistry.refresh()
            virtualDisplay.refresh()
        }
    }

    private func shouldDisableLidCloseDueToSafety() -> Bool {
        if safetySettings.alwaysAllow { return false }

        let battery = currentBatteryPercentage()
        if battery >= 0 && battery < safetySettings.l3DisableBatteryThreshold {
            return true
        }

        let temp = currentThermalStateCelsius()
        if temp >= 0 && temp >= safetySettings.thermalThresholdCelsius {
            return true
        }

        return false
    }

    private func shouldReleaseAllDueToSafety() -> Bool {
        if safetySettings.alwaysAllow { return false }
        let battery = currentBatteryPercentage()
        return battery >= 0 && battery < safetySettings.fullReleaseBatteryThreshold
    }

    // MARK: - Settings Persistence

    private static func loadSavedSettings() -> (
        enabled: Bool,
        lidCloseEnabled: Bool,
        safetySettings: PowerProtectionSafetySettings
    ) {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let lidCloseEnabled = defaults.object(forKey: Self.lidCloseEnabledKey) as? Bool ?? true
        var safetySettings = PowerProtectionSafetySettings()
        if let data = defaults.data(forKey: Self.safetySettingsKey),
           let decoded = try? JSONDecoder().decode(PowerProtectionSafetySettings.self, from: data) {
            safetySettings = decoded
        }
        // Defensive clamp: corrupted or legacy settings may store unreasonable values
        // (e.g. maxLidCloseDuration == 0), which would release L3 immediately.
        if safetySettings.maxLidCloseDuration < 600 {
            safetySettings.maxLidCloseDuration = PowerProtectionSafetySettings().maxLidCloseDuration
        }
        if safetySettings.l3DisableBatteryThreshold < 5 || safetySettings.l3DisableBatteryThreshold > 50 {
            safetySettings.l3DisableBatteryThreshold = PowerProtectionSafetySettings().l3DisableBatteryThreshold
        }
        if safetySettings.fullReleaseBatteryThreshold < 1 || safetySettings.fullReleaseBatteryThreshold > 20 {
            safetySettings.fullReleaseBatteryThreshold = PowerProtectionSafetySettings().fullReleaseBatteryThreshold
        }
        return (enabled, lidCloseEnabled, safetySettings)
    }

    private func saveSafetySettings() {
        if let data = try? JSONEncoder().encode(safetySettings) {
            UserDefaults.standard.set(data, forKey: Self.safetySettingsKey)
        }
    }

    // MARK: - Battery / Thermal Helpers

    private func currentBatteryPercentage() -> Int {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return -1
        }
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let isPresent = info[kIOPSIsPresentKey] as? Bool,
               isPresent,
               let capacity = info[kIOPSCurrentCapacityKey] as? Int {
                return capacity
            }
        }
        return -1
    }

    private func currentThermalStateCelsius() -> Double {
        // Best-effort thermal read. Returns -1 if unavailable.
        // A production implementation may read SMC/AppleSmartBattery sensors via IOKit.
        return -1
    }
}

// MARK: - L1: Assertion Protection

/// Uses `IOPMAssertionCreateWithName` to prevent idle system sleep.
final class AssertionProtection {
    private(set) var isActive = false
    private var assertionID: IOPMAssertionID = 0

    func activate() throws {
        guard !isActive else { return }
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            0,
            "AhaKey Studio: Preventing idle sleep during coding tasks" as CFString,
            &assertionID
        )
        if status == kIOReturnSuccess {
            isActive = true
            log.info("L1 Assertion activated (id: \(self.assertionID))")
        } else {
            throw PowerProtectionError.activationFailed(level: .assertion, reason: "status \(status)")
        }
    }

    func deactivate() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
        log.info("L1 Assertion deactivated")
    }
}

// MARK: - L2: IORegistry Protection

/// Sets the IORegistry `SleepDisabled` hint on the root power domain.
final class IORegistryProtection {
    private(set) var isActive = false
    private var service: io_registry_entry_t = 0

    func activate() throws {
        guard !isActive else { return }
        service = Self.openRootPowerDomain()
        guard service != 0 else {
            throw PowerProtectionError.activationFailed(level: .ioRegistry, reason: NSLocalizedString("无法获取 IOPMrootDomain", comment: ""))
        }
        let result = IORegistryEntrySetCFProperty(service, "SleepDisabled" as CFString, kCFBooleanTrue)
        if result == kIOReturnSuccess {
            isActive = true
            log.info("L2 IORegistry protection activated")
        } else {
            IOObjectRelease(service)
            service = 0
            throw PowerProtectionError.activationFailed(level: .ioRegistry, reason: "status \(result)")
        }
    }

    /// 打开根电源域：`IORegistryEntryFromPath` 在部分 macOS 版本返回 0
    /// （本机实测 14.x 失效），回退到 `IOServiceGetMatchingService`。
    internal static func openRootPowerDomain() -> io_registry_entry_t {
        let byPath = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IOPMrootDomain")
        if byPath != 0 { return byPath }
        return IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    }

    func deactivate() {
        guard isActive, service != 0 else { return }
        IORegistryEntrySetCFProperty(service, "SleepDisabled" as CFString, kCFBooleanFalse)
        IOObjectRelease(service)
        service = 0
        isActive = false
        log.info("L2 IORegistry protection deactivated")
    }

    /// Re-assert the SleepDisabled property in case another process
    /// (e.g. Studio) cleared it externally.
    internal func refresh() {
        guard isActive else { return }
        if service != 0 {
            IORegistryEntrySetCFProperty(service, "SleepDisabled" as CFString, kCFBooleanTrue)
            log.info("L2 IORegistry protection refreshed")
        } else {
            isActive = false
        }
    }
}

// MARK: - Cross-process L3 Coordination

/// Ensures only one process creates a virtual display at a time, preventing
/// redundant CGVirtualDisplay instances when both AhaKey Studio and the Agent
/// request lid-close protection simultaneously.
final class VirtualDisplayCoordinator {
    static let shared = VirtualDisplayCoordinator()

    private let lockURL: URL
    private var lockFd: Int32 = -1

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("AhaKey Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lockURL = dir.appendingPathComponent("virtual-display.lock")
    }

    /// Try to acquire the cross-process lock. Returns true if this process now
    /// owns the lock (and is therefore responsible for creating the display).
    @discardableResult
    func acquire() -> Bool {
        guard lockFd == -1 else { return true }

        let fd = lockURL.path.withCString { open($0, O_CREAT | O_RDWR, 0o644) }
        guard fd >= 0 else { return false }

        let rc = flock(fd, LOCK_EX | LOCK_NB)
        if rc == 0 {
            lockFd = fd
            // Record the owning PID so an admin can identify it.
            ftruncate(fd, 0)
            let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
            _ = pid.withCString { write(fd, $0, strlen($0)) }
            return true
        } else {
            close(fd)
            return false
        }
    }

    var holdsLock: Bool { lockFd >= 0 }

    func release() {
        guard lockFd >= 0 else { return }
        flock(lockFd, LOCK_UN)
        close(lockFd)
        lockFd = -1
    }
}

// MARK: - L3: Virtual Display Protection

/// Creates a virtual display to trick macOS into clamshell mode on lid close.
/// Uses the private CGVirtualDisplay API dynamically discovered at runtime.
final class VirtualDisplayProtection {
    private(set) var isActive = false
    private var virtualDisplay: AhaKeyVirtualDisplay?

    static var isAvailable: Bool {
        AhaKeyVirtualDisplay.isAvailable()
    }

    func activate() throws {
        guard !isActive else { return }

        let acquired = VirtualDisplayCoordinator.shared.acquire()
        if acquired {
            let display = AhaKeyVirtualDisplay(
                name: "AhaKey Virtual Display",
                width: 1920,
                height: 1080,
                refreshRate: 60.0
            )
            guard let display = display else {
                throw PowerProtectionError.activationFailed(level: .virtualDisplay, reason: NSLocalizedString("CGVirtualDisplay 创建失败", comment: ""))
            }
            virtualDisplay = display
            log.info("L3 Virtual display activated (this process owns lock)")
        } else {
            log.info("L3 Virtual display active via peer process lock")
        }
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }

        if VirtualDisplayCoordinator.shared.holdsLock {
            virtualDisplay?.stop()
            virtualDisplay = nil
            VirtualDisplayCoordinator.shared.release()
            log.info("L3 Virtual display deactivated (lock released)")
        } else {
            log.info("L3 Virtual display deactivated (peer owns lock)")
        }
        isActive = false
    }

    /// Re-acquire the virtual-display lock and recreate the display if a peer
    /// process (e.g. Studio) exited and released the lock externally.
    internal func refresh() {
        guard isActive else { return }
        if VirtualDisplayCoordinator.shared.holdsLock {
            if virtualDisplay == nil {
                let display = AhaKeyVirtualDisplay(
                    name: "AhaKey Virtual Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60.0
                )
                if let display = display {
                    virtualDisplay = display
                    log.info("L3 Virtual display recreated (lock retained)")
                } else {
                    log.error("L3 Virtual display recreation failed")
                }
            }
        } else {
            let acquired = VirtualDisplayCoordinator.shared.acquire()
            if acquired {
                let display = AhaKeyVirtualDisplay(
                    name: "AhaKey Virtual Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60.0
                )
                if let display = display {
                    virtualDisplay = display
                    log.info("L3 Virtual display refreshed (took over lock after peer exit)")
                } else {
                    VirtualDisplayCoordinator.shared.release()
                    log.error("L3 Virtual display creation failed after taking lock")
                }
            }
        }
    }
}

// MARK: - Errors

enum PowerProtectionError: LocalizedError {
    case activationFailed(level: PowerProtectionLevel, reason: String)

    var errorDescription: String? {
        switch self {
        case .activationFailed(let level, let reason):
            return String(format: NSLocalizedString("%@ 激活失败: %@", comment: ""), level.description, reason)
        }
    }
}
