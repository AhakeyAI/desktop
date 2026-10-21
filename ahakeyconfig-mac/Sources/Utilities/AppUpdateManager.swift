import AhaKeyConfigShared
import AppKit
import Foundation

@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()
    static let releaseListURL = URL(string: "https://github.com/AhakeyAI/desktop/releases")!

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isVerifying = false
    @Published var availableRelease: AppRelease?
    @Published var statusMessage: String?
    @Published var isVisible = false
    @Published private(set) var downloadedFile: URL?
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64 = 0
    @Published private(set) var bytesPerSecond: Double = 0

    private let session: URLSession
    private let version: String
    private var didCheckThisLaunch = false
    private var apiLimited = false

    init(session: URLSession = .shared, installedVersion: String? = nil) {
        self.session = session
        version = installedVersion ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var installedVersion: String { version }
    var progress: Double? { expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : nil }

    func checkAutomaticallyIfNeeded() {
        guard !didCheckThisLaunch else { return }
        didCheckThisLaunch = true
        Task { await checkForUpdates(manual: false) }
    }

    func checkForUpdates(manual: Bool) async {
        if manual { isVisible = true }
        guard !isChecking && !isDownloading else { return }
        if downloadedFile != nil { return }
        isChecking = true; statusMessage = nil
        defer { isChecking = false }
        do {
            let release = try await latestRelease()
            if release.isNewer(than: installedVersion) {
                availableRelease = release; isVisible = true
            } else {
                availableRelease = nil
                statusMessage = String(format: NSLocalizedString("当前版本 %@ 没有可用的新版本。", comment: ""), installedVersion)
            }
        } catch {
            statusMessage = String(format: NSLocalizedString("检查更新失败：%@", comment: ""), error.localizedDescription)
        }
    }

    private func get(_ url: URL, api: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.setValue("AhaKey-Studio/\(installedVersion)", forHTTPHeaderField: "User-Agent")
        if api { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if api && (status == 403 || status == 429) { apiLimited = true }
        guard status == 200 else { throw UpdateError.releaseHTTP(status) }
        return data
    }

    private func latestRelease() async throws -> AppRelease {
        if !apiLimited {
            do {
                let data = try await get(URL(string: "https://api.github.com/repos/AhakeyAI/desktop/releases/latest")!, api: true)
                return try JSONDecoder().decode(AppRelease.self, from: data)
            } catch is CancellationError { throw CancellationError() }
            catch { /* Public HTML carries the same per-asset digest without API quota. */ }
        }
        let page = try await get(URL(string: "https://github.com/AhakeyAI/desktop/releases/latest")!)
        guard let tag = GitHubReleasePage.tag(in: String(decoding: page, as: UTF8.self)) else { throw URLError(.cannotParseResponse) }
        let assets = try await get(URL(string: "https://github.com/AhakeyAI/desktop/releases/expanded_assets/\(tag)")!)
        return try GitHubReleasePage.release(tag: tag, assetsHTML: String(decoding: assets, as: UTF8.self))
    }

    func download(_ release: AppRelease) async {
        guard !isDownloading else { return }
        isVisible = true
        guard let asset = release.macDMG else {
            statusMessage = NSLocalizedString("该版本没有可校验的 macOS 安装包，请到 GitHub Release 页面下载。", comment: ""); return
        }
        isDownloading = true; isVerifying = false; statusMessage = nil
        receivedBytes = 0; expectedBytes = 0; bytesPerSecond = 0
        defer { isDownloading = false; isVerifying = false }
        let progress = UpdateDownloadProgress { [weak self] received, expected, speed in
            Task { @MainActor in
                guard let self, self.isDownloading, !self.isVerifying else { return }
                self.receivedBytes = received; self.expectedBytes = expected; self.bytesPerSecond = speed
            }
        }
        do {
            var request = URLRequest(url: asset.browserDownloadURL, timeoutInterval: 120)
            request.setValue("AhaKey-Studio/\(installedVersion)", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await session.download(for: request, delegate: progress)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.downloadFailed }
            isVerifying = true
            let destination = try await Task.detached(priority: .utility) {
                guard asset.verifiesSHA256(try Data(contentsOf: temporaryURL, options: .mappedIfSafe)) else {
                    throw UpdateError.checksumMismatch
                }
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
                let filename = "AhaKey-Studio-macOS-\(release.tagName).dmg"
                let destination = Self.uniqueDestination(in: downloads, filename: filename)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                return destination
            }.value
            downloadedFile = destination
            statusMessage = NSLocalizedString("下载完成。点击安装，按提示将应用拖入“应用程序”。", comment: "")
        } catch {
            statusMessage = String(format: NSLocalizedString("下载更新失败：%@", comment: ""), error.localizedDescription)
        }
    }

    func installDownloadedUpdate() {
        guard let downloadedFile else { return }
        if !NSWorkspace.shared.open(downloadedFile) {
            statusMessage = NSLocalizedString("无法打开安装包，请打开文件所在位置后手动安装。", comment: "")
        }
    }

    func revealDownloadedUpdate() {
        guard let downloadedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([downloadedFile])
    }

    nonisolated private static func uniqueDestination(in directory: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(filename), suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).dmg"); suffix += 1
        }
        return candidate
    }

    private enum UpdateError: LocalizedError {
        case releaseHTTP(Int), downloadFailed, checksumMismatch
        var errorDescription: String? {
            switch self {
            case .releaseHTTP(let status): return String(format: NSLocalizedString("GitHub 最新 Release 请求返回 HTTP %d。", comment: ""), status)
            case .downloadFailed: return NSLocalizedString("GitHub 安装包下载失败。", comment: "")
            case .checksumMismatch: return NSLocalizedString("安装包 SHA-256 校验失败，已取消打开。", comment: "")
            }
        }
    }
}

/// URLSession reports bounded progress on its delegate queue; UI mutations stay
/// on MainActor. The session's serial delegate queue owns these counters.
final class UpdateDownloadProgress: NSObject, URLSessionDownloadDelegate {
    private let update: (Int64, Int64, Double) -> Void
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var previousBytes: Int64 = 0
    init(update: @escaping (Int64, Int64, Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - previousTime
        guard elapsed >= 0.2 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        update(totalBytesWritten, totalBytesExpectedToWrite, Double(totalBytesWritten - previousBytes) / max(0.001, elapsed))
        previousBytes = totalBytesWritten; previousTime = now
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
