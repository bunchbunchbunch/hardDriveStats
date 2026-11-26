import Foundation

/// A throwaway folder tree in the temporary directory.
struct TestTree {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "DriveStatsTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Writes `bytes` of real data, optionally backdating its access and modification dates.
    @discardableResult
    func file(_ path: String, bytes: Int, daysOld: Int? = nil) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        if let daysOld {
            var values = URLResourceValues()
            let date = Date(timeIntervalSinceNow: -Double(daysOld) * 86_400)
            values.contentModificationDate = date
            values.contentAccessDate = date
            var mutable = url
            try mutable.setResourceValues(values)
        }
        return url
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
