import Foundation

/// Same trust files, version and last-valid cache for the App and its embedded
/// Agent. No network, polling, user-provided trust key or key-only write grant.
public final class FirmwareRuntimeCatalog: Sendable {
    public static let shared = FirmwareRuntimeCatalog()
    public let store: FirmwareCatalogStore
    public let context: FirmwareDesktopContext
    public struct Snapshot: Sendable {
        public let catalog: VerifiedFirmwareCatalog?
        public let context: FirmwareDesktopContext
        public func permitsPresentation(key: String) -> Bool {
            let decision = FirmwareCatalogDecision.evaluate(identity: .key(key), catalog: catalog, context: context)
            return decision.permitsAdvancedOperations && decision.capabilities.contains(.ws3Display) &&
                decision.capabilities.contains(.ws3Presentation) &&
                catalog?.value.entries.first(where: { $0.key == key })?.visibility != .factory
        }
        public func profile(_ frame: Data, hasValidStatus: Bool) -> FirmwareCapabilityProfile {
            FirmwareCapabilityProfile.probeResponse(frame, hasValidStatusReadback: hasValidStatus, catalog: catalog, context: context)
        }
    }
    public init(bundle: Bundle = FirmwareRuntimeCatalog.applicationBundle(), cacheURL: URL? = FirmwareRuntimeCatalog.defaultCacheURL) {
        func bounded(_ url: URL?, maximum: Int) -> Data? {
            guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= maximum else { return nil }
            return try? Data(contentsOf: url)
        }
        let keys = bounded(bundle.url(forResource: "FirmwareCatalogTrust", withExtension: "json", subdirectory: "FirmwareFlasher"), maximum: 65_536)
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
        let embedded = bounded(bundle.url(forResource: "FirmwareCatalog", withExtension: "json", subdirectory: "FirmwareFlasher"), maximum: 2_097_152)
        store = FirmwareCatalogStore(publicKeys: keys, embeddedEnvelope: embedded, cacheURL: cacheURL)
        context = .init(version: FirmwareDesktopVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            ?? FirmwareDesktopVersion("0.0.0")!)
    }
    public func snapshot() async -> Snapshot {
        await store.reloadPersistedIfChanged()
        return Snapshot(catalog: await store.snapshot().catalog, context: context)
    }
    public static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AhaKeyStudio/FirmwareCatalog/verified-envelope.json")
    }
    public static func applicationBundle(main: Bundle = .main, executable: URL? = Bundle.main.executableURL) -> Bundle {
        if main.bundleURL.pathExtension == "app" { return main }
        // A bare embedded Agent's Bundle.main can point at Contents/MacOS.
        if let executable {
            let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if app.pathExtension == "app", let bundle = Bundle(url: app), bundle.bundleIdentifier == "lab.jawa.ahakeyconfig" {
                return bundle
            }
        }
        return main
    }
}
