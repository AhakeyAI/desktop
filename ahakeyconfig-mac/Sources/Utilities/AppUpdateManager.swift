import AhaKeyConfigShared
import AppKit
import Foundation

@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published var availableRelease: AppRelease?
    @Published var statusMessage: String?

    private let releaseAPI = URL(string: "https://api.github.com/repos/AhakeyAI/desktop/releases/latest")!
    private let lastCheckKey = "appUpdate.lastSuccessfulCheck"
    private var didCheckThisLaunch = false

    private init() {}

    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkAutomaticallyIfNeeded() {
        guard !didCheckThisLaunch else { return }
        didCheckThisLaunch = true
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        Task { await checkForUpdates(manual: false) }
    }

    func checkForUpdates(manual: Bool) async {
        guard !isChecking && !isDownloading else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: releaseAPI)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("AhaKey-Studio/\(installedVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.releaseUnavailable
            }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            if release.isNewer(than: installedVersion) {
                availableRelease = release
            } else if manual {
                statusMessage = "当前版本 \(installedVersion) 没有可用的新版本。"
            }
        } catch {
            if manual { statusMessage = "检查更新失败：\(error.localizedDescription)" }
        }
    }

    func download(_ release: AppRelease) async {
        guard !isDownloading else { return }
        guard let asset = release.macDMG else {
            statusMessage = "该版本没有可校验的 macOS 安装包，请到 GitHub Release 页面下载。"
            return
        }
        isDownloading = true
        defer { isDownloading = false }

        do {
            var request = URLRequest(url: asset.browserDownloadURL)
            request.timeoutInterval = 120
            request.setValue("AhaKey-Studio/\(installedVersion)", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.downloadFailed
            }
            guard asset.verifiesSHA256(try Data(contentsOf: temporaryURL)) else {
                throw UpdateError.checksumMismatch
            }

            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
            let filename = "AhaKey-Studio-macOS-\(release.tagName).dmg"
            let destination = uniqueDestination(in: downloads, filename: filename)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            let opened = NSWorkspace.shared.open(destination)
            statusMessage = opened
                ? "已下载并打开 \(destination.lastPathComponent)。请在安装窗口中将 AhaKey Studio 拖入“应用程序”。"
                : "已下载到 \(destination.path)。请双击安装包，将 AhaKey Studio 拖入“应用程序”。"
        } catch {
            statusMessage = "下载更新失败：\(error.localizedDescription)"
        }
    }

    private func uniqueDestination(in directory: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    private enum UpdateError: LocalizedError {
        case releaseUnavailable, downloadFailed, checksumMismatch

        var errorDescription: String? {
            switch self {
            case .releaseUnavailable: return "无法读取 GitHub 最新 Release。"
            case .downloadFailed: return "GitHub 安装包下载失败。"
            case .checksumMismatch: return "安装包 SHA-256 校验失败，已取消打开。"
            }
        }
    }
}
