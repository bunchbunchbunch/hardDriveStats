import Foundation

/// What's in the user's Trash.
struct TrashInfo: Sendable {
    var folder: URL
    var size: Int64
    /// Items at the top of the Trash, as Finder counts them (hidden files like .DS_Store aside).
    var itemCount: Int
    /// Top-level folders and files of 1 MB or more, largest first.
    var items: [FileNode]
    /// False when macOS wouldn't let Drive Stats look inside, which takes Full Disk Access.
    var isReadable: Bool

    static let userTrash = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")

    var smallItemCount: Int { max(0, itemCount - items.count) }
    var smallItemBytes: Int64 { max(0, size - items.reduce(0) { $0 + $1.size }) }

    static func measure(_ folder: URL = userTrash) async throws -> TrashInfo {
        let result = try await DiskScanner(fileThreshold: 1_000_000).scan(folder)
        let visible = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return TrashInfo(
            folder: folder,
            size: result.root.size,
            itemCount: visible.count,
            items: result.root.children.filter { !$0.name.hasPrefix(".") },
            isReadable: !result.unreadable.contains { $0.path == folder.path }
        )
    }
}
