import Foundation
import Testing

struct ScannerTests {
    let scanner = DiskScanner(fileThreshold: 1_000_000)

    @Test func totalsSizesAndKeepsOnlyBigFiles() async throws {
        let tree = try TestTree()
        defer { tree.remove() }
        let big = try tree.file("a/big.bin", bytes: 3_000_000)
        try tree.file("a/small.txt", bytes: 1_000)
        try tree.file("b/c/deep.bin", bytes: 2_000_000)
        try FileManager.default.createSymbolicLink(at: tree.root.appending(path: "link"), withDestinationURL: URL(filePath: "/"))

        let result = try await scanner.scan(tree.root)
        let root = result.root

        #expect(root.fileCount == 4) // big, small, deep, and the link itself (not followed)
        #expect(root.size >= 5_000_000)
        #expect(root.size < 6_000_000)
        #expect(root.children.map(\.name) == ["a", "b"]) // largest first; the tiny link is rolled up
        #expect(root.smallFileCount == 1)

        let a = try #require(root.node(at: tree.root.appending(path: "a")))
        #expect(a.children.map(\.url.path) == [big.path])
        #expect(a.smallFileCount == 1)
        #expect(a.size == a.children[0].size + a.smallFileBytes)
        #expect(root.node(at: tree.root.appending(path: "b/c/deep.bin"))?.isDirectory == false)
        #expect(result.unreadable.isEmpty)
    }

    @Test func notesFoldersItCannotRead() async throws {
        let tree = try TestTree()
        let locked = try tree.folder("locked")
        try tree.file("locked/secret.bin", bytes: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            tree.remove()
        }

        let result = try await scanner.scan(tree.root)

        #expect(result.unreadable.map(\.path) == [locked.path])
    }

    @Test func removingANodeUpdatesEveryAncestor() async throws {
        let tree = try TestTree()
        defer { tree.remove() }
        let doomed = try tree.file("x/y/doomed.bin", bytes: 2_000_000)
        try tree.file("x/keep.bin", bytes: 1_500_000)

        var root = try await scanner.scan(tree.root).root
        let before = root.size
        let x = tree.root.appending(path: "x")
        let xBefore = try #require(root.node(at: x)).size

        let removal = root.remove(doomed)
        let removed = try #require(removal)
        let again = root.remove(doomed)

        #expect(removed.files == 1)
        #expect(root.size == before - removed.bytes)
        #expect(root.node(at: x)?.size == xBefore - removed.bytes)
        #expect(root.node(at: doomed) == nil)
        #expect(again == nil)
    }

    @Test func cancellingStopsTheScan() async throws {
        let tree = try TestTree()
        defer { tree.remove() }
        try tree.file("a/b/c.txt", bytes: 10)

        let task = Task { try await scanner.scan(tree.root) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
