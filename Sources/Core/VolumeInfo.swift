import Foundation

/// Capacity of one mounted disk.
struct VolumeInfo: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var total: Int64
    /// Empty space plus purgeable space macOS clears on demand. Finder calls this "available".
    var available: Int64
    /// Space that's empty right now.
    var free: Int64
    var isStartup: Bool

    var id: String { url.path }
    var used: Int64 { total - available }
    var purgeable: Int64 { max(0, available - free) }

    private static let keys: Set<URLResourceKey> = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsRootFileSystemKey,
    ]

    init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: Self.keys),
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        self.url = url
        name = values.volumeName ?? url.lastPathComponent
        self.total = Int64(total)
        free = Int64(values.volumeAvailableCapacity ?? 0)
        available = values.volumeAvailableCapacityForImportantUsage ?? free
        isStartup = values.volumeIsRootFileSystem ?? false
    }

    /// Visible mounted disks, startup disk first.
    static func mounted() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap(VolumeInfo.init(url:)).sorted { $0.isStartup && !$1.isStartup }
    }
}
