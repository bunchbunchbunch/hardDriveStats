import Foundation
import Testing

struct HistoryStoreTests {
    @Test func recordsAtMostOneSnapshotPerSpacing() throws {
        let tree = try TestTree()
        defer { tree.remove() }
        let store = HistoryStore(file: tree.root.appending(path: "nested/history.json"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try store.record(DiskSnapshot(date: start, total: 1000, available: 400))
        _ = try store.record(DiskSnapshot(date: start + 600, total: 1000, available: 390))
        let history = try store.record(DiskSnapshot(date: start + 7200, total: 1000, available: 300))

        #expect(history.map(\.used) == [600, 700])
        #expect(store.load() == history)
    }

    @Test func startsEmptyWithoutAFile() {
        let store = HistoryStore(file: URL(filePath: "/nonexistent/history.json"))
        #expect(store.load().isEmpty)
    }
}
