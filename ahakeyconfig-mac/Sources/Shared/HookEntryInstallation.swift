import Foundation

public struct HookEntrySelfCheck: Codable, Equatable {
    public static let argument = "--hook-self-check"
    public static let executableName = "ahakey-hook"
    public static let current = HookEntrySelfCheck(product: executableName, protocolVersion: 1)

    public let product: String
    public let protocolVersion: Int
}

/// Local evidence for the current fixed Codex entry. No session ID or Hook payload is retained.
public struct CodexHookInstallation {
    public struct EntryIdentity: Codable, Equatable {
        let inode: UInt64
        let device: UInt64
        let size: UInt64
        let modified: Date

        public init?(at url: URL) {
            let files = FileManager.default
            guard files.isExecutableFile(atPath: url.path),
                  let attributes = try? files.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let inode = attributes[.systemFileNumber] as? NSNumber,
                  let device = attributes[.systemNumber] as? NSNumber,
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date else { return nil }
            self.inode = inode.uint64Value
            self.device = device.uint64Value
            self.size = size.uint64Value
            self.modified = modified
        }
    }

    public struct Status: Equatable {
        public let configurationWritten: Bool
        public let entryChecked: Bool
        public let eventReceived: Bool
        public let restartRequired: Bool
    }

    private struct Receipt: Codable {
        let generation: UUID
        let configuration: String
        let entry: EntryIdentity
        let restartRequired: Bool
    }

    private let directory: URL
    public init(directory: URL = AhaKeyPaths.applicationSupportDirectory) { self.directory = directory }

    public var entryURL: URL {
        directory.appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(HookEntrySelfCheck.executableName)
    }

    private var receiptURL: URL { directory.appendingPathComponent("codex-hook-installation.json") }

    private var receipt: Receipt? {
        guard let data = try? Data(contentsOf: receiptURL) else { return nil }
        return try? JSONDecoder().decode(Receipt.self, from: data)
    }

    private func eventURL(_ generation: UUID) -> URL {
        directory.appendingPathComponent("codex-hook-event-\(generation.uuidString)")
    }

    public func confirm(configuration: String, entry: EntryIdentity, migrated: Bool) throws {
        let previous = receipt
        if previous?.configuration == configuration, previous?.entry == entry { return }
        let restartRequired = migrated || previous.map {
            $0.restartRequired && !FileManager.default.fileExists(atPath: eventURL($0.generation).path)
        } == true
        let next = Receipt(generation: UUID(), configuration: configuration, entry: entry, restartRequired: restartRequired)
        try JSONEncoder().encode(next).write(to: receiptURL, options: .atomic)
        if let previous { try? FileManager.default.removeItem(at: eventURL(previous.generation)) }
    }

    /// A per-tool repair can replace the shared entry without editing Codex's configuration.
    public func confirmEntryUpgrade(_ entry: EntryIdentity) throws {
        guard let receipt, receipt.entry != entry else { return }
        try confirm(configuration: receipt.configuration, entry: entry, migrated: false)
    }

    public func status(configuration: String?) -> Status? {
        guard let receipt else { return nil }
        let configurationWritten = configuration == receipt.configuration
        let entryChecked = EntryIdentity(at: entryURL) == receipt.entry
        let eventReceived = configurationWritten && entryChecked
            && FileManager.default.fileExists(atPath: eventURL(receipt.generation).path)
        return Status(configurationWritten: configurationWritten, entryChecked: entryChecked,
                      eventReceived: eventReceived, restartRequired: configurationWritten && receipt.restartRequired)
    }

    public func clear() {
        let previous = receipt
        try? FileManager.default.removeItem(at: receiptURL)
        if let previous { try? FileManager.default.removeItem(at: eventURL(previous.generation)) }
    }

    /// Binds the event to the installation that existed when the Hook program started.
    public func eventRecorder(executablePath: String) -> (_ expectedEvent: String, _ context: [String: Any]) -> Void {
        guard executablePath == entryURL.path, let receipt,
              EntryIdentity(at: entryURL) == receipt.entry else { return { _, _ in } }
        let url = eventURL(receipt.generation)
        return { expectedEvent, context in
            guard context["hook_event_name"] as? String == expectedEvent,
                  let session = context["session_id_short"] as? String, !session.isEmpty,
                  self.receipt?.generation == receipt.generation,
                  !FileManager.default.fileExists(atPath: url.path) else { return }
            try? Data().write(to: url, options: .atomic)
        }
    }
}
