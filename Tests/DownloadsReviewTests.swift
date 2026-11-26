import Foundation
import Testing

struct DownloadsReviewTests {
    func verdict(_ name: String, isDirectory: Bool = false, isPackage: Bool = false, origin: DownloadOrigin = DownloadOrigin(),
                 siblings: Set<String> = [], zipHasApp: Bool = false) -> DownloadItem.Verdict {
        DownloadsReviewer.verdict(name: name, isDirectory: isDirectory, isPackage: isPackage, origin: origin,
                                  siblings: siblings, zipContainsApp: { zipHasApp }).0
    }

    let web = DownloadOrigin(agent: "Safari", whereFroms: ["https://dl.google.com/chrome/mac/googlechrome.dmg", "https://www.google.com/chrome/"])
    let mail = DownloadOrigin(agent: "Mail", whereFroms: ["Grandma <grandma@example.com>", "message:%3Cabc@example.com%3E"])
    let gmail = DownloadOrigin(agent: "Google Chrome", whereFroms: ["https://mail-attachment.googleusercontent.com/attachment/u/0/x", "https://mail.google.com/"])

    @Test func clearsInstallersAppsAndUnfinishedDownloads() {
        #expect(verdict("googlechrome.dmg", origin: web) == .redownloadable)
        #expect(verdict("Firefox.app", isDirectory: true, isPackage: true) == .redownloadable)
        #expect(verdict("node-v22.pkg") == .redownloadable)
        #expect(verdict("big-video.mp4.crdownload") == .redownloadable)
        #expect(verdict("Setup.EXE") == .redownloadable)
    }

    @Test func keepsPhotosDocumentsAndAnythingFromEmail() {
        #expect(verdict("IMG_2041.HEIC", origin: web) == .keep)
        #expect(verdict("taxes-2025.pdf", origin: web) == .keep)
        #expect(verdict("party.mov") == .keep)
        // Email wins over everything, even a file type that would otherwise go.
        #expect(verdict("photos.zip", origin: mail) == .keep)
        #expect(verdict("scan.zip", origin: gmail) == .keep)
        #expect(verdict("installer.dmg", origin: mail) == .keep)
    }

    @Test func clearsArchivesOnlyWhenTheyreClearlyRedundant() {
        #expect(verdict("project.zip", siblings: ["project.zip", "project"]) == .redownloadable)
        #expect(verdict("tool-1.2.tar.gz", siblings: ["tool-1.2"]) == .redownloadable)
        #expect(verdict("Rectangle.zip", siblings: ["Rectangle.app"]) == .redownloadable)
        #expect(verdict("Browser.zip", zipHasApp: true) == .redownloadable)
        #expect(verdict("takeout-2025.zip", origin: web) == .unsure)
        #expect(verdict("backup.tar.gz", zipHasApp: true) == .unsure) // only zips get looked inside
    }

    @Test func isUnsureAboutFoldersAndUnknownFiles() {
        #expect(verdict("Some Folder", isDirectory: true) == .unsure)
        #expect(verdict("data.json") == .unsure)
    }

    @Test func reviewsARealFolderWithDownloadMetadata() async throws {
        let tree = try TestTree()
        defer { tree.remove() }
        let chrome = try tree.file("googlechrome.dmg", bytes: 2_000_000)
        try setAttribute("com.apple.quarantine", Data("0083;6560f5a1;Safari;".utf8), on: chrome)
        try setAttribute("com.apple.metadata:kMDItemWhereFroms",
                         try PropertyListSerialization.data(fromPropertyList: web.whereFroms, format: .binary, options: 0), on: chrome)
        let photo = try tree.file("vacation.zip", bytes: 1_000_000)
        try setAttribute("com.apple.quarantine", Data("0083;6560f5a1;Mail;".utf8), on: photo)
        try tree.file("Firefox.app/Contents/MacOS/firefox", bytes: 500_000)
        try tree.file("notes.json", bytes: 10)
        try tree.file(".DS_Store", bytes: 10)

        let items = try await DownloadsReviewer(folder: tree.root, zipContainsApp: { _ in false }).review()
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

        #expect(items.map(\.name) == ["googlechrome.dmg", "Firefox.app", "notes.json", "vacation.zip"])
        #expect(byName["googlechrome.dmg"]?.source == "dl.google.com")
        #expect(byName["vacation.zip"]?.verdict == .keep)
        #expect(byName["vacation.zip"]?.source == "Mail")
        #expect(byName["Firefox.app"]?.verdict == .redownloadable)
        #expect((byName["Firefox.app"]?.size ?? 0) >= 500_000)
        #expect(byName["notes.json"]?.verdict == .unsure)
    }

    @Test func findsAnAppInsideARealZip() throws {
        let tree = try TestTree()
        defer { tree.remove() }
        try tree.file("Browser.app/Contents/Info.plist", bytes: 10)
        try tree.file("pictures/cat.jpg", bytes: 10)
        try zip("Browser.app", into: "browser.zip", in: tree.root)
        try zip("pictures", into: "pictures.zip", in: tree.root)

        #expect(DownloadsReviewer.zipListsApp(tree.root.appending(path: "browser.zip")))
        #expect(!DownloadsReviewer.zipListsApp(tree.root.appending(path: "pictures.zip")))
    }

    private func setAttribute(_ name: String, _ value: Data, on url: URL) throws {
        let result = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, 0) }
        if result != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    private func zip(_ item: String, into archive: String, in folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zip")
        process.arguments = ["-qr", archive, item]
        process.currentDirectoryURL = folder
        try process.run()
        process.waitUntilExit()
    }
}
