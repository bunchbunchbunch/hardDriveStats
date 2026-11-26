import Foundation
import Testing

/// Builds a fake home folder, scans it, and checks which paths get suggested.
struct RecommenderTests {
    let mb = 1_000_000

    func recommendations(_ build: (TestTree) throws -> Void, appLastOpened: @escaping @Sendable (URL) -> Date? = { _ in nil }) async throws -> [String: Recommendation] {
        let tree = try TestTree()
        defer { tree.remove() }
        try build(tree)
        let root = try await DiskScanner(fileThreshold: 1_000_000).scan(tree.root).root
        let recommender = Recommender(
            home: tree.root, minimumSize: Int64(mb), largeFileSize: Int64(3 * mb),
            staleDays: 90, unusedAppDays: 180, appLastOpened: appLastOpened
        )
        let recs = recommender.recommendations(for: root)
        // Key by path relative to the fake home.
        return Dictionary(uniqueKeysWithValues: recs.map { (String($0.url.path.dropFirst(tree.root.path.count + 1)), $0) })
    }

    @Test func suggestsKnownCachesAndDeveloperFolders() async throws {
        let recs = try await recommendations { tree in
            try tree.file("Library/Developer/Xcode/DerivedData/App-abc/Build/out.o", bytes: 2 * mb)
            try tree.file("Library/Caches/com.example.app/blob", bytes: 2 * mb)
            try tree.file("Library/Caches/com.apple.thing/blob", bytes: 2 * mb)
            try tree.file("Library/Caches/tiny/blob", bytes: 1_000)
            try tree.file(".Trash/old.zip", bytes: 2 * mb)
        }

        #expect(recs["Library/Developer/Xcode/DerivedData"]?.safety == .safe)
        #expect(recs["Library/Caches/com.example.app"]?.safety == .safe)
        #expect(recs["Library/Caches/com.apple.thing"]?.safety == .review)
        #expect(recs["Library/Caches/tiny"] == nil)
        #expect(recs[".Trash"]?.canTrash == false)
        #expect(recs.count == 4)
    }

    @Test func suggestsProjectBuildFoldersOnlyInRealProjects() async throws {
        let recs = try await recommendations { tree in
            try tree.file("Code/web/package.json", bytes: 100)
            try tree.file("Code/web/node_modules/react/index.js", bytes: 2 * mb)
            try tree.file("Code/web/node_modules/react/package.json", bytes: 100)
            try tree.file("Code/web/node_modules/react/node_modules/x/x.js", bytes: 2 * mb)
            try tree.file("Code/notAProject/node_modules/x.js", bytes: 2 * mb)
            try tree.file("Code/tool/Package.swift", bytes: 100)
            try tree.file("Code/tool/.build/debug/tool", bytes: 2 * mb)
            try tree.file("Code/py/.venv/pyvenv.cfg", bytes: 100)
            try tree.file("Code/py/.venv/lib/torch.so", bytes: 2 * mb)
            // An editor extension's dependencies belong to the editor, not to you.
            try tree.file(".vscode/extensions/ext/package.json", bytes: 100)
            try tree.file(".vscode/extensions/ext/node_modules/dep.js", bytes: 2 * mb)
            try tree.file("Library/Application Support/Code/package.json", bytes: 100)
            try tree.file("Library/Application Support/Code/node_modules/dep.js", bytes: 2 * mb)
        }

        #expect(recs["Code/web/node_modules"]?.safety == .rebuildable)
        #expect(recs["Code/web/node_modules"]?.title == "node_modules in web")
        #expect(recs["Code/tool/.build"] != nil)
        #expect(recs["Code/py/.venv"] != nil)
        #expect(recs.keys.sorted() == ["Code/py/.venv", "Code/tool/.build", "Code/web/node_modules"])
    }

    @Test func suggestsInstallersOldDownloadsAndStaleLargeFiles() async throws {
        let recs = try await recommendations { tree in
            try tree.file("Downloads/Setup.dmg", bytes: 2 * mb)
            try tree.file("Downloads/old-project/data.csv", bytes: 2 * mb, daysOld: 200)
            try tree.file("Downloads/new-project/data.csv", bytes: 2 * mb, daysOld: 5)
            try tree.file("Movies/old-render.mov", bytes: 4 * mb, daysOld: 400)
            try tree.file("Movies/new-render.mov", bytes: 4 * mb, daysOld: 10)
            try tree.file("Movies/old-small.mov", bytes: 2 * mb, daysOld: 400)
            // Never look inside packages, like a photo library or an app.
            try tree.file("Pictures/Old.app/Contents/Resources/huge.bin", bytes: 4 * mb, daysOld: 400)
        }

        #expect(recs["Downloads/Setup.dmg"]?.reason.contains("installer") == true)
        #expect(recs["Downloads/old-project"]?.safety == .review)
        #expect(recs["Movies/old-render.mov"]?.lastUsed != nil)
        #expect(recs.keys.sorted() == ["Downloads/Setup.dmg", "Downloads/old-project", "Movies/old-render.mov"])
    }

    @Test func suggestsAppsNotOpenedInMonths() async throws {
        let old = Date(timeIntervalSinceNow: -300 * 86_400)
        let recs = try await recommendations({ tree in
            try tree.file("Applications/Old.app/Contents/MacOS/Old", bytes: 2 * mb)
            try tree.file("Applications/Fresh.app/Contents/MacOS/Fresh", bytes: 2 * mb)
            try tree.file("Applications/Unknown.app/Contents/MacOS/Unknown", bytes: 2 * mb)
        }, appLastOpened: { url in
            switch url.lastPathComponent {
            case "Old.app": old
            case "Fresh.app": Date()
            default: nil
            }
        })

        #expect(recs.keys.sorted() == ["Applications/Old.app"])
        #expect(recs["Applications/Old.app"]?.title == "Old")
        #expect(recs["Applications/Old.app"]?.lastUsed == old)
    }

    @Test func leavesFilesOutsideTheHomeFolderAlone() async throws {
        let tree = try TestTree()
        defer { tree.remove() }
        // A system folder: disk images and big files here belong to macOS.
        try tree.file("System/Library/AssetsV2/runtime.dmg", bytes: 2 * mb)
        try tree.file("System/Library/model.bin", bytes: 4 * mb, daysOld: 400)
        try tree.folder("home")
        let system = tree.root.appending(path: "System")
        let root = try await DiskScanner(fileThreshold: 1_000_000).scan(system).root
        let recommender = Recommender(home: tree.root.appending(path: "home"), minimumSize: Int64(mb), largeFileSize: Int64(3 * mb))

        #expect(recommender.recommendations(for: root).isEmpty)
    }

    @Test func keepsOnlyTheOutermostOfOverlappingSuggestions() async throws {
        let recs = try await recommendations { tree in
            // DerivedData inside a project's ignored build folder would match twice.
            try tree.file("Code/web/package.json", bytes: 100)
            try tree.file("Code/web/node_modules/DerivedData/x.o", bytes: 2 * mb)
            try tree.file("Code/web/node_modules/big.iso", bytes: 4 * mb)
        }

        #expect(recs.keys.sorted() == ["Code/web/node_modules"])
    }
}
