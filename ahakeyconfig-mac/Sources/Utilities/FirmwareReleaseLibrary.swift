import Foundation
import Combine
import AhaKeyConfigShared

/// Release configuration is supplied by the signed App bundle, never by the
/// downloaded catalog itself. An unconfigured test build has no public releases.
@MainActor
final class FirmwareReleaseLibrary: ObservableObject {
    @Published private(set) var candidates: [FirmwareInstallCandidate] = []
    @Published private(set) var identity: FirmwareCatalogIdentity = .readFailed
    @Published private(set) var message: String?
    @Published private(set) var isBusy = false
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var catalog: VerifiedFirmwareCatalog?
    private let store: FirmwareCatalogStore
    private let context: FirmwareDesktopContext
    private let bundle: Bundle
    private let refreshURL: URL?
    private let hasTrustKeys: Bool
    private var preparedURL: URL?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        let trustURL = bundle.url(forResource: "FirmwareCatalogTrust", withExtension: "json", subdirectory: "FirmwareFlasher")
        let keys = trustURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
        hasTrustKeys = !keys.isEmpty
        let runtime = bundle.bundleURL == FirmwareRuntimeCatalog.applicationBundle().bundleURL
            ? FirmwareRuntimeCatalog.shared : FirmwareRuntimeCatalog(bundle: bundle)
        store = runtime.store
        context = runtime.context
        refreshURL = (bundle.object(forInfoDictionaryKey: "AhaKeyFirmwareCatalogURL") as? String).flatMap(URL.init(string:))
    }
    deinit { if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) } }
    var canRefresh: Bool { hasTrustKeys && refreshURL?.scheme == "https" }
    var decision: FirmwareCatalogDecision { .evaluate(identity: identity, catalog: catalog, context: context) }

    func matchingCandidate(sha256: String, byteCount: Int) -> FirmwareInstallCandidate? {
        guard let entry = FirmwareCandidateSelection.trustedLocalMatch(sha256: sha256, catalog: catalog, context: context),
              entry.artifact?.byteCount == byteCount else { return nil }
        return candidates.first { $0.entry == entry && $0.canInstall }
    }

    func load() async {
        catalog = await store.snapshot().catalog
        rebuild()
    }
    func readIdentity(ble: AhaKeyBLEManager, session: StudioInspectorSession) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            identity = try await session.withConnection { _ in
                let profile = try await ble.readFirmwareCapabilityProfile(forceStatusReadback: true)
                switch profile.identity {
                case .knownWS2Catalog: return .key(FirmwareCapabilityProfile.ws2CatalogKey)
                case .verifiedCatalog(let key, _): return .key(key)
                case .legacy: return .legacy
                case .unknown(let key): return key.map(FirmwareCatalogIdentity.key) ?? .readFailed
                }
            }
            message = nil
        } catch {
            identity = .readFailed
            message = KeyboardSettingsFeedback.message(for: error)
        }
        rebuild()
    }
    func refresh() async {
        guard !isBusy, canRefresh, let refreshURL else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await FirmwareReleaseHTTP.read(refreshURL, maximumBytes: 2_097_152)
            catalog = try await store.acceptRefresh(data).catalog
            message = NSLocalizedString("固件版本列表已更新。", comment: "")
        } catch { message = NSLocalizedString("版本列表更新失败，已保留原列表。", comment: "") }
        rebuild()
    }
    func prepare(_ candidate: FirmwareInstallCandidate) async throws -> URL {
        guard !isBusy, let current = candidates.first(where: { $0.entry.key == candidate.entry.key }),
              current == candidate, candidate.canInstall, let artifact = candidate.entry.artifact else {
            throw FirmwareArtifactVerification.Failure.incompatibleCandidate
        }
        isBusy = true; downloadProgress = 0
        defer { isBusy = false; downloadProgress = nil }
        let data: Data
        if let path = artifact.bundledPath, let root = bundle.resourceURL {
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
            let url = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(resolvedRoot.path + "/"),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == artifact.byteCount else {
                throw FirmwareArtifactVerification.Failure.wrongSize
            }
            data = try Data(contentsOf: url)
        } else if let url = artifact.downloadURL {
            data = try await FirmwareReleaseHTTP.read(url, maximumBytes: artifact.byteCount) { [weak self] count in
                self?.downloadProgress = Double(count) / Double(artifact.byteCount)
            }
        } else { throw FirmwareArtifactVerification.Failure.missingArtifact }
        try Task.checkCancellation()
        try FirmwareArtifactVerification.verify(data, candidate: candidate)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AhaKeyRelease-\(UUID().uuidString).hex")
        try data.write(to: url, options: .atomic)
        if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
        preparedURL = url
        downloadProgress = 1
        return url
    }
    private func rebuild() {
        candidates = FirmwareCandidateSelection.candidates(catalog: catalog, identity: identity, context: context)
    }
}

private enum FirmwareReleaseHTTP {
    enum Failure: Error { case insecureURL, badResponse, tooLarge }
    /// No account credentials/cookies and no automatic retry or background poll.
    static func read(_ url: URL, maximumBytes: Int,
        progress: (@MainActor (Int) -> Void)? = nil) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil else { throw Failure.insecureURL }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https" else { throw Failure.badResponse }
        guard response.expectedContentLength <= maximumBytes else { throw Failure.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw Failure.tooLarge }
            data.append(byte)
            if data.count.isMultiple(of: 65_536) { await progress?(data.count) }
        }
        return data
    }
}
