import Foundation

// MARK: - Models

enum VoiceHistoryKind: String, Codable, CaseIterable, Identifiable {
    case dictation
    case askAnything

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: "听写"
        case .askAnything: "问任何问题"
        }
    }
}

enum VoiceHistoryStatus: String, Codable {
    case ok
    case cancelled
    case failed
}

struct VoiceHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var text: String
    var kind: VoiceHistoryKind
    var status: VoiceHistoryStatus

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        kind: VoiceHistoryKind = .dictation,
        status: VoiceHistoryStatus = .ok
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.kind = kind
        self.status = status
    }
}

struct VoiceDictionaryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var phrase: String
    var replacement: String
    var enabled: Bool

    init(
        id: UUID = UUID(),
        phrase: String,
        replacement: String,
        enabled: Bool = true
    ) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement
        self.enabled = enabled
    }
}

enum VoiceHistoryRetention: String, Codable, CaseIterable, Identifiable {
    case forever
    case days7
    case days30
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever: "永远"
        case .days7: "7 天"
        case .days30: "30 天"
        case .never: "不保存"
        }
    }

    var maxAge: TimeInterval? {
        switch self {
        case .forever: return nil
        case .days7: return 7 * 24 * 60 * 60
        case .days30: return 30 * 24 * 60 * 60
        case .never: return 0
        }
    }
}

// MARK: - Store

@MainActor
final class VoiceInputStore: ObservableObject {
    static let shared = VoiceInputStore()

    @Published private(set) var history: [VoiceHistoryEntry] = []
    @Published private(set) var dictionary: [VoiceDictionaryEntry] = []
    @Published var retention: VoiceHistoryRetention {
        didSet {
            persist()
            pruneHistoryIfNeeded()
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct Snapshot: Codable {
        var retention: VoiceHistoryRetention
        var history: [VoiceHistoryEntry]
        var dictionary: [VoiceDictionaryEntry]
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("AhaKeyStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("voice-input-store.json")

        if let data = try? Data(contentsOf: fileURL),
           let snap = try? decoder.decode(Snapshot.self, from: data) {
            retention = snap.retention
            history = snap.history.sorted { $0.createdAt > $1.createdAt }
            dictionary = snap.dictionary
        } else {
            retention = .forever
            history = []
            dictionary = []
        }
        pruneHistoryIfNeeded()
    }

    // MARK: History

    func appendDictation(text: String, status: VoiceHistoryStatus = .ok) {
        guard retention != .never else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || status != .ok else { return }
        let entry = VoiceHistoryEntry(
            text: trimmed.isEmpty ? "转录已被取消。" : trimmed,
            kind: .dictation,
            status: status
        )
        history.insert(entry, at: 0)
        pruneHistoryIfNeeded()
        persist()
    }

    func deleteHistory(id: UUID) {
        history.removeAll { $0.id == id }
        persist()
    }

    func clearHistory() {
        history = []
        persist()
    }

    func filteredHistory(kind: VoiceHistoryKind?) -> [VoiceHistoryEntry] {
        guard let kind else { return history }
        return history.filter { $0.kind == kind }
    }

    func historyGroupedByDay(kind: VoiceHistoryKind?) -> [(day: Date, entries: [VoiceHistoryEntry])] {
        let cal = Calendar.current
        let items = filteredHistory(kind: kind)
        let grouped = Dictionary(grouping: items) { entry in
            cal.startOfDay(for: entry.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }

    // MARK: Dictionary

    func addDictionaryEntry(phrase: String, replacement: String) {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !r.isEmpty else { return }
        dictionary.insert(VoiceDictionaryEntry(phrase: p, replacement: r), at: 0)
        persist()
    }

    func updateDictionaryEntry(_ entry: VoiceDictionaryEntry) {
        guard let idx = dictionary.firstIndex(where: { $0.id == entry.id }) else { return }
        dictionary[idx] = entry
        persist()
    }

    func deleteDictionaryEntry(id: UUID) {
        dictionary.removeAll { $0.id == id }
        persist()
    }

    func applyDictionary(to text: String) -> String {
        let enabled = dictionary.filter(\.enabled).sorted { $0.phrase.count > $1.phrase.count }
        guard !enabled.isEmpty else { return text }
        var result = text
        for entry in enabled {
            result = result.replacingOccurrences(of: entry.phrase, with: entry.replacement)
        }
        return result
    }

    // MARK: Private

    private func pruneHistoryIfNeeded() {
        guard let maxAge = retention.maxAge else { return }
        if maxAge == 0 {
            if !history.isEmpty {
                history = []
                persist()
            }
            return
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let next = history.filter { $0.createdAt >= cutoff }
        if next.count != history.count {
            history = next
            persist()
        }
    }

    private func persist() {
        let snap = Snapshot(retention: retention, history: history, dictionary: dictionary)
        guard let data = try? encoder.encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
