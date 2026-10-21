import SwiftUI

struct AppUpdateCard: View {
    @ObservedObject var manager: AppUpdateManager
    var body: some View {
        if manager.isVisible {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(NSLocalizedString("软件更新", comment: ""), systemImage: "arrow.down.circle")
                        .font(.headline)
                    Spacer()
                    Button { manager.isVisible = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel(NSLocalizedString("关闭", comment: ""))
                }
                if manager.isChecking {
                    ProgressView(NSLocalizedString("检查更新中", comment: ""))
                } else if manager.isDownloading {
                    Text(manager.isVerifying ? NSLocalizedString("正在校验安装包…", comment: "") : NSLocalizedString("正在下载更新…", comment: ""))
                    if let value = manager.progress { ProgressView(value: value) } else { ProgressView() }
                    Text("\(ByteCountFormatter.string(fromByteCount: manager.receivedBytes, countStyle: .file)) / \(manager.expectedBytes > 0 ? ByteCountFormatter.string(fromByteCount: manager.expectedBytes, countStyle: .file) : "—") · \(ByteCountFormatter.string(fromByteCount: Int64(manager.bytesPerSecond), countStyle: .file))/s")
                        .font(.caption).foregroundStyle(.secondary)
                } else if manager.downloadedFile != nil {
                    Text(manager.statusMessage ?? "")
                    HStack {
                        Button(NSLocalizedString("安装更新", comment: "")) { manager.installDownloadedUpdate() }.buttonStyle(.borderedProminent)
                        Button(NSLocalizedString("打开文件位置", comment: "")) { manager.revealDownloadedUpdate() }
                    }
                } else if let release = manager.availableRelease {
                    Text(String(format: NSLocalizedString("当前版本 %@，最新版本 %@。", comment: ""), manager.installedVersion, release.tagName))
                    if let message = manager.statusMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button(NSLocalizedString("稍后", comment: "")) { manager.isVisible = false }
                        if release.macDMG != nil {
                            Button(NSLocalizedString("下载更新", comment: "")) { Task { await manager.download(release) } }.buttonStyle(.borderedProminent)
                        } else {
                            Link(NSLocalizedString("前往Github", comment: ""), destination: AppUpdateManager.releaseListURL)
                        }
                    }
                } else {
                    Text(manager.statusMessage ?? "")
                    Button(NSLocalizedString("重试检查", comment: "")) { Task { await manager.checkForUpdates(manual: true) } }
                }
            }
            .padding(16).frame(width: 330, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(18)
        }
    }
}
