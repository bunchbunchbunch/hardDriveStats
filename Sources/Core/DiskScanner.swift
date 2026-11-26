import Foundation
import Synchronization

/// Live counts from a scan in progress, safe to read from any thread.
final class ScanProgress: Sendable {
    struct Snapshot: Sendable {
        var files = 0
        var bytes: Int64 = 0
        var folder = ""
        /// Folders the scan wasn't allowed to read, usually for lack of Full Disk Access.
        var unreadable: [URL] = []
    }

    private let state = Mutex(Snapshot())

    var snapshot: Snapshot { state.withLock { $0 } }

    func add(files: Int, bytes: Int64, folder: String) {
        state.withLock {
            $0.files += files
            $0.bytes += bytes
            $0.folder = folder
        }
    }

    func noteUnreadable(_ folder: URL) {
        state.withLock { $0.unreadable.append(folder) }
    }
}

struct ScanResult: Sendable {
    var root: FileNode
    var unreadable: [URL]
    var finished: Date
}

/// Walks a folder tree and totals what each folder uses on disk.
struct DiskScanner: Sendable {
    /// Files at least this big appear on their own; smaller ones are only counted.
    var fileThreshold: Int64 = 10_000_000
    /// Folders this close to the root are scanned in parallel.
    var parallelDepth = 2

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isVolumeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentAccessDateKey, .contentModificationDateKey,
    ]

    @concurrent
    func scan(_ root: URL, progress: ScanProgress = ScanProgress()) async throws -> ScanResult {
        let isPackage = (try? root.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        let node = try await scanFolder(root, isPackage: isPackage, depth: 0, progress: progress)
        return ScanResult(root: node, unreadable: progress.snapshot.unreadable, finished: .now)
    }

    /// Special folders at the root that show the whole disk again under another name.
    private static let rootAliases: Set<String> = ["/.nofollow", "/.resolve", "/.vol"]

    @concurrent
    private func scanFolder(_ folder: URL, isPackage: Bool, depth: Int, progress: ScanProgress) async throws -> FileNode {
        try Task.checkCancellation()
        var node = FileNode(url: folder, isDirectory: true, isPackage: isPackage)
        // A listing hands back autoreleased objects. Scanning a whole subtree can run as one
        // uninterrupted job, so without a pool per folder they pile up into gigabytes.
        let subfolders = autoreleasepool { readFolder(into: &node, progress: progress) }

        var folders: [FileNode] = []
        if depth < parallelDepth {
            folders = try await withThrowingTaskGroup(of: FileNode.self) { group in
                for sub in subfolders {
                    group.addTask {
                        try await scanFolder(sub.url, isPackage: sub.isPackage, depth: depth + 1, progress: progress)
                    }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }
        } else {
            for sub in subfolders {
                folders.append(try await scanFolder(sub.url, isPackage: sub.isPackage, depth: depth + 1, progress: progress))
            }
        }

        for folder in folders {
            node.size += folder.size
            node.fileCount += folder.fileCount
            node.lastUsed = latest(node.lastUsed, folder.lastUsed)
        }
        node.children += folders
        node.children.sort { $0.size > $1.size }
        return node
    }

    /// Adds `folder`'s files to `node` and returns its subfolders.
    private func readFolder(into node: inout FileNode, progress: ScanProgress) -> [(url: URL, isPackage: Bool)] {
        let folder = node.url
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(Self.keys), options: []
            )
        } catch {
            progress.noteUnreadable(folder)
            return []
        }

        var subfolders: [(url: URL, isPackage: Bool)] = []
        for item in items {
            guard let values = try? item.resourceValues(forKeys: Self.keys) else { continue }
            // Listings can spell the parent differently (/private/var for /var), so build
            // child URLs from the folder's own URL to keep paths consistent with the root.
            if values.isDirectory == true && values.isSymbolicLink != true {
                let url = folder.appending(path: item.lastPathComponent, directoryHint: .isDirectory)
                // A mount point is another disk; its space isn't this one's.
                if values.isVolume != true && !Self.rootAliases.contains(url.path) {
                    subfolders.append((url, values.isPackage ?? false))
                }
                continue
            }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let used = latest(values.contentAccessDate, values.contentModificationDate)
            node.size += size
            node.fileCount += 1
            node.lastUsed = latest(node.lastUsed, used)
            if size >= fileThreshold {
                let url = folder.appending(path: item.lastPathComponent, directoryHint: .notDirectory)
                node.children.append(FileNode(url: url, isDirectory: false, size: size, fileCount: 1, lastUsed: used))
            } else {
                node.smallFileBytes += size
                node.smallFileCount += 1
            }
        }
        progress.add(files: node.fileCount, bytes: node.size, folder: folder.path)
        return subfolders
    }
}
