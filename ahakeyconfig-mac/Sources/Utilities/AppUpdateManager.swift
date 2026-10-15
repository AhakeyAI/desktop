import AhaKeyConfigShared
import AppKit
import Foundation

@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()
    static let releaseListURL = URL(string: "https://github.com/AhakeyAI/desktop/releases")!

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
            let data = try await loadLatestReleaseData()
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            if release.isNewer(than: installedVersion) {
                availableRelease = release
            } else if manual {
                statusMessage = String(format: NSLocalizedString("当前版本 %@ 没有可用的新版本。", comment: ""), installedVersion)
            }
        } catch {
            if manual {
                statusMessage = String(format: NSLocalizedString("检查更新失败：%@", comment: ""), error.localizedDescription)
            }
        }
    }

    private func loadLatestReleaseData() async throws -> Data {
        // 优先尊重系统代理。本机代理出口的 GitHub API 匿名配额耗尽时，
        // 仅针对公开 Release 元数据尝试一次直连。
        var request = URLRequest(url: releaseAPI)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AhaKey-Studio/\(installedVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 200 { return data }
        if status == 403 || status == 429 {
            let api = releaseAPI
            let version = installedVersion
            if let direct = try? await Task.detached(priority: .utility, operation: {
                try GitHubReleaseTransport.fetchDirect(api: api, version: version)
            }).value {
                return direct
            }
        }
        throw UpdateError.releaseHTTP(status)
    }

    func download(_ release: AppRelease) async {
        guard !isDownloading else { return }
        guard let asset = release.macDMG else {
            statusMessage = NSLocalizedString("该版本没有可校验的 macOS 安装包，请到 GitHub Release 页面下载。", comment: "")
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
                ? String(format: NSLocalizedString("已下载并打开 %@。请在安装窗口中将 AhaKey Studio 拖入“应用程序”。", comment: ""), destination.lastPathComponent)
                : String(format: NSLocalizedString("已下载到 %@。请双击安装包，将 AhaKey Studio 拖入“应用程序”。", comment: ""), destination.path)
        } catch {
            statusMessage = String(format: NSLocalizedString("下载更新失败：%@", comment: ""), error.localizedDescription)
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
        case releaseHTTP(Int), downloadFailed, checksumMismatch

        var errorDescription: String? {
            switch self {
            case .releaseHTTP(let status):
                return String(format: NSLocalizedString("GitHub 最新 Release 请求返回 HTTP %d。", comment: ""), status)
            case .downloadFailed: return NSLocalizedString("GitHub 安装包下载失败。", comment: "")
            case .checksumMismatch: return NSLocalizedString("安装包 SHA-256 校验失败，已取消打开。", comment: "")
            }
        }
    }
}

private enum GitHubReleaseTransport {
    static func fetchDirect(api: URL, version: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--silent", "--show-error", "--fail", "--location",
            "--connect-timeout", "8", "--max-time", "20",
            "--noproxy", "api.github.com",
            "--header", "Accept: application/vnd.github+json",
            "--header", "User-Agent: AhaKey-Studio/\(version)",
            api.absoluteString,
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.cannotConnectToHost) }
        return data
    }
}
