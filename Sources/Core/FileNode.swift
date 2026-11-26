import Foundation

/// A folder, or a file big enough to show on its own, from a disk scan.
///
/// Folders always keep their subfolders. Files under the scan's size threshold are only
/// counted, in `smallFileBytes` and `smallFileCount`, which keeps a scan of millions of
/// files small in memory.
struct FileNode: Identifiable, Hashable, Sendable {
    var url: URL
    var isDirectory: Bool
    var isPackage = false
    /// Bytes allocated on disk, including everything beneath.
    var size: Int64 = 0
    /// Files beneath this folder, or 1 for a file.
    var fileCount = 0
    /// Most recent access or modification of anything beneath.
    var lastUsed: Date?
    /// Largest first.
    var children: [FileNode] = []
    var smallFileBytes: Int64 = 0
    var smallFileCount = 0

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// The node at `target`, if it is this node or lies beneath it.
    func node(at target: URL) -> FileNode? {
        let path = target.path
        if path == url.path { return self }
        return children.first { path.isWithin($0.url.path) }?.node(at: target)
    }

    /// Removes the node at `target` from beneath this one, updating sizes along the way.
    /// Returns the bytes and files removed, or nil if `target` isn't beneath this node.
    @discardableResult
    mutating func remove(_ target: URL) -> (bytes: Int64, files: Int)? {
        let path = target.path
        guard let index = children.firstIndex(where: { path.isWithin($0.url.path) }) else { return nil }
        let removed: (bytes: Int64, files: Int)
        if children[index].url.path == path {
            removed = (children[index].size, children[index].fileCount)
            children.remove(at: index)
        } else {
            guard let inner = children[index].remove(target) else { return nil }
            removed = inner
            children.sort { $0.size > $1.size }
        }
        size -= removed.bytes
        fileCount -= removed.files
        return removed
    }
}

extension String {
    /// True when this path is `folder` or lies inside it.
    func isWithin(_ folder: String) -> Bool {
        self == folder || hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}

/// The later of two optional dates.
func latest(_ a: Date?, _ b: Date?) -> Date? {
    guard let a, let b else { return a ?? b }
    return max(a, b)
}
