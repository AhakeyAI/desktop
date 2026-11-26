import CryptoKit
import Foundation

/// A callback is evidence for one installation generation and executable.
/// Only the generation is recorded. Tool input and session data stay out of the receipt.
public struct StatusHookReceipts {
    public enum Client: String, CaseIterable { case workBuddy, copilot, antigravity, openCode, cline, pi, openClaw }

    private struct Installation: Codable {
        let generation: UUID
        let configuration: String
        let entry: CodexHookInstallation.EntryIdentity
    }

    private let directory: URL
    private var entryURL: URL { CodexHookInstallation(directory: directory).entryURL }

    public init(directory: URL = AhaKeyPaths.applicationSupportDirectory) {
        self.directory = directory
    }

    public func confirm(client: Client, configuration: URL) throws {
        try confirm(client: client, configurations: [configuration])
    }

    public func confirm(client: Client, configurations: [URL]) throws {
        guard let entry = CodexHookInstallation.EntryIdentity(at: entryURL),
              let fingerprint = fingerprint(of: configurations)
        else { throw CocoaError(.fileReadCorruptFile) }
        let previous = installation(client)
        if previous?.configuration == fingerprint, previous?.entry == entry { return }
        try replace(client, configuration: fingerprint, entry: entry, previous: previous)
    }

    /// The shared binary may be updated by installing a different tool's hook.
    public func confirmEntryUpgrade(_ entry: CodexHookInstallation.EntryIdentity) throws {
        for client in Client.allCases {
            guard let previous = installation(client), previous.entry != entry else { continue }
            try replace(client, configuration: previous.configuration, entry: entry, previous: previous)
        }
    }

    private func replace(_ client: Client, configuration: String, entry: CodexHookInstallation.EntryIdentity,
                         previous: Installation?) throws {
        let next = Installation(generation: UUID(), configuration: configuration, entry: entry)
        try JSONEncoder().encode(next).write(to: installationURL(client), options: .atomic)
        if let previous { try? FileManager.default.removeItem(at: eventURL(client, previous.generation)) }
    }

    public func isVerified(client: Client, configuration: URL) -> Bool {
        isVerified(client: client, configurations: [configuration])
    }

    public func isVerified(client: Client, configurations: [URL]) -> Bool {
        guard let receipt = installation(client),
              FileManager.default.fileExists(atPath: eventURL(client, receipt.generation).path),
              receipt.entry == CodexHookInstallation.EntryIdentity(at: entryURL)
        else { return false }
        return receipt.configuration == fingerprint(of: configurations)
    }

    public func clear(client: Client) {
        let previous = installation(client)
        try? FileManager.default.removeItem(at: installationURL(client))
        if let previous { try? FileManager.default.removeItem(at: eventURL(client, previous.generation)) }
    }

    public func eventRecorder(client: Client, executablePath: String) -> () -> Void {
        let invokedEntry = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        guard invokedEntry.path == entryURL.resolvingSymlinksInPath().path,
              let receipt = installation(client),
              receipt.entry == CodexHookInstallation.EntryIdentity(at: entryURL) else { return {} }
        let target = eventURL(client, receipt.generation)
        return {
            guard installation(client)?.generation == receipt.generation else { return }
            // The file itself is the receipt. A no-clobber create is atomic
            // and avoids Foundation staging it outside the allowed directory.
            try? Data().write(to: target, options: .withoutOverwriting)
        }
    }

    private func installation(_ client: Client) -> Installation? {
        guard let data = try? Data(contentsOf: installationURL(client)) else { return nil }
        return try? JSONDecoder().decode(Installation.self, from: data)
    }

    private func installationURL(_ client: Client) -> URL {
        directory.appendingPathComponent("\(client.rawValue)-hook-installation.json")
    }

    private func eventURL(_ client: Client, _ generation: UUID) -> URL {
        directory.appendingPathComponent("\(client.rawValue)-hook-event-\(generation.uuidString)")
    }

    private func fingerprint(of configuration: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: configuration) else { return nil }
        defer { try? handle.close() }
        let limit = 2 * 1_024 * 1_024
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fingerprint(of configurations: [URL]) -> String? {
        let digests = configurations.map { fingerprint(of: $0) }
        let present = digests.compactMap { $0 }
        guard !present.isEmpty, present.count == digests.count else { return nil }
        return present.joined(separator: ":")
    }
}
