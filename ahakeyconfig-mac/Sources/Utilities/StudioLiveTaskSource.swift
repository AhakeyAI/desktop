import Foundation
import AhaKeyConfigShared

/// Watches only the active connection's journal. Reads on actual file changes;
/// bounded lock retries are one-shot, never a heartbeat or directory scan loop.
@MainActor
final class StudioLiveTaskSource {
    private let directory: URL
    private var lease: WS3LiveTaskJournal.Lease?
    private var monitor: DispatchSourceFileSystemObject?
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?
    private var lastSequence: UInt64 = 0
    private var consume: (([WS3LiveTaskEvent], Bool) -> Void)?
    private var fault: (() -> Void)?
    init(directory: URL = WS3LiveTaskJournal.productionDirectory) { self.directory = directory }
    deinit {
        refreshTask?.cancel()
        monitor?.cancel()
        if let lease { WS3LiveTaskJournal.end(lease, directory: directory) }
    }
    func start(consume: @escaping ([WS3LiveTaskEvent], Bool) -> Void, fault: @escaping () -> Void) throws {
        stop()
        let lease = try WS3LiveTaskJournal.begin(directory: directory)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            WS3LiveTaskJournal.end(lease, directory: directory)
            throw CocoaError(.fileReadUnknown)
        }
        self.lease = lease; self.consume = consume; self.fault = fault
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .revoke], queue: .main)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self, weak source] in
            let flags = source?.data ?? []
            Task { @MainActor [weak self, weak source] in
                guard let self, let source, self.monitor === source else { return }
                if !flags.intersection([.rename, .delete, .revoke]).isEmpty {
                    let report = self.fault
                    self.stop(); report?()
                } else { self.scheduleRefresh() }
            }
        }
        source.setRegistrationHandler { [weak self, weak source] in
            Task { @MainActor [weak self, weak source] in
                guard let self, let source, self.monitor === source else { return }
                let current = open(self.directory.path, O_EVTONLY)
                var watched = stat(), actual = stat()
                let sameDirectory = current >= 0 && fstat(fd, &watched) == 0 && fstat(current, &actual) == 0 &&
                    watched.st_dev == actual.st_dev && watched.st_ino == actual.st_ino
                if current >= 0 { close(current) }
                guard sameDirectory else {
                    let report = self.fault
                    self.stop(); report?(); return
                }
                self.scheduleRefresh()
            }
        }
        monitor = source; source.resume()
    }
    func stop() {
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        monitor?.cancel(); monitor = nil
        if let lease { WS3LiveTaskJournal.end(lease, directory: directory) }
        lease = nil; lastSequence = 0; consume = nil; fault = nil
    }
    /// Also used by deterministic tests of registration races and coalescing.
    @discardableResult
    func refresh() -> Bool {
        guard let lease, let batch = WS3LiveTaskJournal.read(lease, directory: directory),
              batch.sequence >= lastSequence, batch.sequence >= UInt64(batch.events.count) else { return false }
        guard batch.sequence > lastSequence else { return true }
        let firstSequence = batch.sequence - UInt64(batch.events.count)
        let gap = firstSequence > lastSequence
        let skip = Int(min(lastSequence > firstSequence ? lastSequence - firstSequence : 0, UInt64(batch.events.count)))
        let events = Array(batch.events.dropFirst(skip))
        lastSequence = batch.sequence
        consume?(events, gap)
        return true
    }
    private func scheduleRefresh() {
        guard refreshTask == nil else { return } // Fixed coalescing window; a busy producer cannot postpone delivery forever.
        let nonce = lease?.nonce, id = UUID()
        refreshID = id
        refreshTask = Task { @MainActor [weak self] in
            defer { if self?.refreshID == id { self?.refreshTask = nil; self?.refreshID = nil } }
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self, self.lease?.nonce == nonce else { return }
                if self.refresh() { return }
            }
        }
    }
}
