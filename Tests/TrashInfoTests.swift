import Foundation
import Testing

struct TrashInfoTests {
    @Test func countsVisibleItemsAndListsTheBigOnes() async throws {
        let tree = try TestTree()
        defer { tree.remove() }
        try tree.file("old.zip", bytes: 2_000_000)
        try tree.file("Project/build/app.bin", bytes: 3_000_000)
        try tree.file("note.txt", bytes: 10)
        try tree.file(".DS_Store", bytes: 10)

        let trash = try await TrashInfo.measure(tree.root)

        #expect(trash.isReadable)
        #expect(trash.itemCount == 3) // .DS_Store isn't an item
        #expect(trash.items.map(\.name) == ["Project", "old.zip"])
        #expect(trash.smallItemCount == 1)
        #expect(trash.size >= 5_000_000)
        #expect(trash.size == trash.items.reduce(0) { $0 + $1.size } + trash.smallItemBytes)
    }

    @Test func reportsATrashItCannotRead() async throws {
        let tree = try TestTree()
        let trash = try tree.folder("Trash")
        try tree.file("Trash/secret.bin", bytes: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trash.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trash.path)
            tree.remove()
        }

        let info = try await TrashInfo.measure(trash)

        #expect(!info.isReadable)
        #expect(info.size == 0)
    }

    @Test func startsEmpty() async throws {
        let tree = try TestTree()
        defer { tree.remove() }

        let trash = try await TrashInfo.measure(tree.root)

        #expect(trash.isReadable)
        #expect(trash.itemCount == 0)
        #expect(trash.size == 0)
    }
}
