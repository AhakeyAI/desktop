import Foundation
import AhaKeyConfigShared

/// CLI defaults are separate from live Desktop/TUI session permissions.
/// Management journals only the owned scalar and restores its prior value.
enum KimiConfigLeverSync {
    private static var hooksProbeCache: (path: String, modified: Date, result: Bool)?

    static func hasAhaKeyHooks(at url: URL = KimiConfigPolicySync.productionConfigURL) -> Bool {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return false
        }
        if let cache = hooksProbeCache, cache.path == url.path, cache.modified == modified { return cache.result }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let result = KimiHooksConfiguration.containsManagedHook(in: text)
        hooksProbeCache = (url.path, modified, result)
        return result
    }

    @discardableResult
    static func synchronizeManaged(switchState: Int?, configURL: URL = KimiConfigPolicySync.productionConfigURL,
                                   controlDirectory: URL = ApprovalAutomationControl.productionDirectory) -> Bool {
        let managedState = hasAhaKeyHooks(at: configURL) ? switchState : nil
        let layout: KimiConfigPolicySync.Layout = KimiConfigLocation.isLegacy(configURL) ? .legacyPython : .nativeV2
        switch KimiManagedPermissionDefaults.synchronize(switchState: managedState, configURL: configURL,
                                                          controlDirectory: controlDirectory, layout: layout) {
        case .updated, .restored, .unchanged, .userOverride: return true
        default: return false
        }
    }

    @discardableResult
    static func apply(switchStateAuto: Bool, activeConfigURL: URL = KimiConfigPolicySync.productionConfigURL) -> Bool {
        synchronizeManaged(switchState: switchStateAuto ? 0 : 1, configURL: activeConfigURL)
    }

    static func diagnosticSnapshotForLog() -> [String: Any] {
        KimiConfigDiagnostic.snapshotForLog()
    }
}
