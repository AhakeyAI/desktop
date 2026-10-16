import Foundation
import AhaKeyConfigShared

enum KimiConfigLeverSync {
    static func apply(switchStateAuto: Bool) {
        let outcome = KimiConfigPolicySync.apply(auto: switchStateAuto)
        KimiHookDebugLog.append(event: "kimi_policy_sync", details: ["outcome": String(describing: outcome)])
        KimiHookDebugLog.stderrLine("Disk policy synchronized when valid; running sessions may need /reload and persisted /yolo off.")
    }
    static func diagnosticSnapshotForLog() -> [String: Any] {
        var result = KimiConfigDiagnostic.snapshotForLog()
        result["leverSnapshotBakExists"] = FileManager.default.fileExists(atPath: KimiConfigPolicySync.productionConfigURL.appendingPathExtension("ahakey.lever0.bak").path)
        return result
    }
}
