import Foundation

/// 将键盘拨杆与 Kimi **`~/.kimi/config.toml`** 的根级 **`default_yolo`** 对齐：**自动档 `true`，手动档 `false`**。
///
/// 不使用「整文件恢复快照」来代表手动档：快照往往在用户原本就开启过 YOLO 时记下 `default_yolo=true`，一还原无论怎样 `/reload` 都会回到 YOLO。自动档仍可在首次写入前备份一份 **`.ahakey.lever0.bak`** 供你以后自行比对；切到手动档时会删掉该快照以免再次误还原。
enum KimiConfigLeverSync {
    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi/config.toml", isDirectory: false)
    }

    private static var snapshotURL: URL { configURL.appendingPathExtension("ahakey.lever0.bak") }

    static func apply(switchStateAuto: Bool) {
        if switchStateAuto {
            enableYoloInConfig()
        } else {
            disableDefaultYoloForManualDial()
        }
    }

    private static func enableYoloInConfig() {
        let fm = FileManager.default
        let path = configURL.path
        guard fm.fileExists(atPath: path) else {
            fprintStderr("KimiConfigLeverSync: 未找到 \(path)，跳过。\n")
            KimiHookDebugLog.append(event: "kimi_lever_sync_missing_config", details: ["path": path])
            return
        }

        if !fm.fileExists(atPath: snapshotURL.path) {
            do {
                try fm.copyItem(at: configURL, to: snapshotURL)
                KimiHookDebugLog.append(event: "kimi_lever_sync_backup_created", details: ["to": snapshotURL.path])
            } catch {
                fprintStderr("KimiConfigLeverSync: 备份失败 \(error.localizedDescription)\n")
                KimiHookDebugLog.append(event: "kimi_lever_sync_backup_failed", details: ["error": error.localizedDescription])
            }
        }

        guard let data = fm.contents(atPath: path),
              var raw = String(data: data, encoding: .utf8) else {
            fprintStderr("KimiConfigLeverSync: 无法读取 \(path)\n")
            return
        }
        raw = replaceOrInsertDefaultYolo(raw, template: #"default_yolo = true  # AhaKey: dial auto; run /reload in Kimi after changing dial"#)
        writeRaw(raw, label: "enable_auto")
    }

    private static func disableDefaultYoloForManualDial() {
        let fm = FileManager.default
        let path = configURL.path
        // 删掉旧逻辑用的快照：手动档若用它「整文件还原」会把原先的 default_yolo=true 整块带回来。
        if fm.fileExists(atPath: snapshotURL.path) {
            do {
                try fm.removeItem(at: snapshotURL)
                KimiHookDebugLog.append(event: "kimi_lever_snapshot_removed_for_manual_clear", details: [:])
                KimiHookDebugLog.stderrLine("removed config.toml.ahakey.lever0.bak (avoid restoring old default_yolo=true)")
            } catch {
                fprintStderr("KimiConfigLeverSync: 无法删除快照 \(error.localizedDescription)\n")
            }
        }
        guard fm.fileExists(atPath: path) else { return }
        guard let data = fm.contents(atPath: path),
              var raw = String(data: data, encoding: .utf8) else { return }
        raw = replaceOrInsertDefaultYolo(raw, template: #"default_yolo = false  # AhaKey: dial manual; run /reload in Kimi after changing dial"#)
        writeRaw(raw, label: "disable_manual")
        KimiHookDebugLog.stderrLine("default_yolo=false on dial manual; run /reload in Kimi.")
        // kimi-cli: effective_yolo = load_config.default_yolo OR session persist state.json approval.yolo
        KimiHookDebugLog.stderrLine(
            "note: kimi ORs persisted session YOLO (e.g. after /yolo) with config — if reload still shows yolo, toggle /yolo off once or use a fresh session."
        )
    }

    private static func replaceOrInsertDefaultYolo(_ text: String, template: String) -> String {
        let pattern = #"(?m)^\s*default_yolo\s*=\s*[^\r\n]*\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return template + "\n\n" + text
        }
        let nsFull = text as NSString
        let fullRange = NSRange(location: 0, length: nsFull.length)
        if regex.firstMatch(in: text, options: [], range: fullRange) != nil {
            return regex.stringByReplacingMatches(in: text, options: [], range: fullRange, withTemplate: template)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return template + "\n" }
        return template + "\n\n" + text
    }

    private static func writeRaw(_ raw: String, label: String) {
        guard let out = raw.data(using: .utf8) else { return }
        do {
            try out.write(to: configURL, options: .atomic)
            KimiHookDebugLog.append(event: "kimi_lever_sync_\(label)", details: [
                "bytes": out.count,
                "reloadHint": "kimi_reload_slash_same_session_ok",
            ])
        } catch {
            fprintStderr("KimiConfigLeverSync: 写回失败 \(error.localizedDescription)\n")
            KimiHookDebugLog.append(event: "kimi_lever_sync_write_failed", details: ["error": error.localizedDescription])
        }
    }

    private static func fprintStderr(_ s: String) {
        FileHandle.standardError.write(Data(s.utf8))
    }

    /// 供 `permission-request.log`：`kimiLeverDebug`。
    static func diagnosticSnapshotForLog() -> [String: Any] {
        var d = KimiConfigDiagnostic.snapshotForLog()
        d["leverSnapshotBakExists"] = FileManager.default.fileExists(atPath: snapshotURL.path)
        return d
    }
}
