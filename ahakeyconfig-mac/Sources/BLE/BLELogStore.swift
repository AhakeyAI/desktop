import AhaKeyConfigShared
import Combine
import Foundation

/// 通信日志条目
struct BLELogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}

/// 内存诊断级日志 Store（阶段 2：三级日志）。
/// 独立 ObservableObject：append 只触发观察 logStore 的 View 刷新，
/// 不再像旧 `commLog` 那样波及所有观察 `AhaKeyBLEManager` 的 View。
/// 收默认永久级全部内容 + 一次性运行信息（diagnostic）；周期 TX/RX 不进这里。
///
/// 临时详细级（TX/RX 抓包）：默认关闭，开启 15 分钟后自动关闭；
/// 原始流量写后台串行队列 + 滚动文件（ble-verbose.log，5MB×3），不进内存。
@MainActor
final class BLELogStore: ObservableObject {
    /// 内存诊断级日志（最近 200 条）
    @Published private(set) var entries: [BLELogEntry] = []
    private let maxEntries = 200

    // MARK: - 临时详细级（TX/RX 抓包）

    /// 详细会话到期时间；nil 表示未开启。UI 据此显示开关与剩余时间。
    @Published private(set) var verboseSessionExpiresAt: Date?
    var isVerboseLoggingEnabled: Bool { verboseSessionExpiresAt != nil }

    private var verboseSession = VerboseLogSessionController()
    private var verboseAutoStopTimer: Timer?
    private let verboseLogWriter: RotatingLogFile
    /// 抓包文件写入专用后台串行队列
    private let verboseQueue = DispatchQueue(
        label: "lab.jawa.ahakeyconfig.ble-verbose-log",
        qos: .utility
    )

    /// 详细抓包日志路径（自 AhaKeyBLEManager 迁入；Studio 诊断窗口边界）。
    nonisolated static var verboseLogFileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ble-verbose.log")
    }

    init(verboseLogFileURL: URL = BLELogStore.verboseLogFileURL) {
        verboseLogWriter = RotatingLogFile(fileURL: verboseLogFileURL)
    }

    func append(_ entry: BLELogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: - 详细会话开关

    func setVerboseLoggingEnabled(_ enabled: Bool) {
        if enabled {
            verboseSession.start(now: Date())
            verboseSessionExpiresAt = verboseSession.endDate
            verboseAutoStopTimer?.invalidate()
            verboseAutoStopTimer = Timer.scheduledTimer(
                withTimeInterval: verboseSession.duration,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleVerboseAutoStop()
                }
            }
            append(BLELogEntry(timestamp: Date(), message: NSLocalizedString("详细日志已开启，15 分钟后自动关闭（原始 TX/RX 写入 ble-verbose.log）", comment: ""), isError: false))
        } else {
            guard isVerboseLoggingEnabled else { return }
            stopVerboseSession()
            append(BLELogEntry(timestamp: Date(), message: NSLocalizedString("详细日志已关闭", comment: ""), isError: false))
        }
    }

    private func handleVerboseAutoStop() {
        guard verboseSession.advance(to: Date()) else { return }
        stopVerboseSession()
        append(BLELogEntry(timestamp: Date(), message: NSLocalizedString("详细日志已到 15 分钟，自动关闭", comment: ""), isError: false))
    }

    private func stopVerboseSession() {
        verboseSession.stop()
        verboseSessionExpiresAt = nil
        verboseAutoStopTimer?.invalidate()
        verboseAutoStopTimer = nil
    }

    /// 详细级抓包写文件（后台串行队列，不进内存）。仅会话开启时由 manager 调用。
    func writeVerboseLine(_ line: String) {
        verboseQueue.async { [verboseLogWriter] in
            try? verboseLogWriter.append(line)
        }
    }
}
