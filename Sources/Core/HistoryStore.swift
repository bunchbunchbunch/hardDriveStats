import Foundation

/// The startup disk's capacity at one moment.
struct DiskSnapshot: Codable, Hashable, Sendable {
    var date: Date
    var total: Int64
    var available: Int64

    var used: Int64 { total - available }
}

/// Keeps a history of startup disk snapshots in a JSON file.
struct HistoryStore: Sendable {
    var file: URL

    static let standard = HistoryStore(
        file: URL.applicationSupportDirectory.appending(path: "Drive Stats/history.json")
    )

    func load() -> [DiskSnapshot] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([DiskSnapshot].self, from: data)) ?? []
    }

    /// Saves `snapshot` unless the latest saved one is less than `spacing` seconds older,
    /// and returns the whole history.
    func record(_ snapshot: DiskSnapshot, spacing: TimeInterval = 3600) throws -> [DiskSnapshot] {
        var history = load()
        if let last = history.last, snapshot.date.timeIntervalSince(last.date) < spacing { return history }
        history.append(snapshot)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: file, options: .atomic)
        return history
    }
}
