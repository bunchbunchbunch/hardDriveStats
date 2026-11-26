import Foundation

/// One item at the top of the Downloads folder, and whether it's easy to get again.
struct DownloadItem: Identifiable, Hashable, Sendable {
    enum Verdict: Int, CaseIterable, Sendable {
        /// Installers, apps, and other things a website will hand you again.
        case redownloadable
        case unsure
        /// Photos, documents, and email attachments, which may be hard to replace.
        case keep
    }

    var url: URL
    var isDirectory: Bool
    var size: Int64
    /// When it landed in Downloads.
    var added: Date?
    /// Where it came from: a website, or the app that saved it.
    var source: String?
    var verdict: Verdict
    var reason: String

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// Where a download came from, read from the metadata macOS attaches to downloaded files.
struct DownloadOrigin: Sendable {
    /// The app that saved it, such as Safari, Chrome, or Mail.
    var agent: String?
    /// The download address and the page it came from, or the sender and message for a Mail attachment.
    var whereFroms: [String] = []

    private static let emailAgents: Set<String> = ["Mail", "Microsoft Outlook", "Outlook", "Spark", "Airmail", "Mimestream", "Thunderbird", "Superhuman", "Canary Mail"]
    private static let emailSites = ["mail.google.com", "mail-attachment.googleusercontent.com", "outlook.live.com", "outlook.office.com", "outlook.office365.com", "mail.yahoo.com", "icloud.com/mail", "mail.proton.me", "fastmail.com"]

    var isEmail: Bool {
        if let agent, Self.emailAgents.contains(agent) { return true }
        return whereFroms.contains { from in
            from.hasPrefix("message:") || Self.emailSites.contains { from.contains($0) }
                || (from.contains("@") && !from.contains("://")) // a sender address
        }
    }

    /// The website it came from, if it came from one.
    var host: String? {
        whereFroms.lazy.compactMap { URL(string: $0) }.first { $0.scheme?.hasPrefix("http") == true }?.host()
    }

    static func read(_ url: URL) -> DownloadOrigin {
        var origin = DownloadOrigin()
        // "0083;6560f5a1;Safari;8A3F..." names the app that downloaded the file.
        if let data = attribute("com.apple.quarantine", of: url) {
            let fields = String(decoding: data, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
            if fields.count > 2, !fields[2].isEmpty { origin.agent = String(fields[2]) }
        }
        if let data = attribute("com.apple.metadata:kMDItemWhereFroms", of: url),
           let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
            origin.whereFroms = list
        }
        return origin
    }

    private static func attribute(_ name: String, of url: URL) -> Data? {
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, length, 0, 0) }
        return read == length ? data : nil
    }
}

/// Sorts what's in Downloads into things to clear out, things to look at, and things to keep.
struct DownloadsReviewer: Sendable {
    var folder: URL
    /// Whether a zip holds an app. Reads the zip's listing by default; tests substitute their own.
    var zipContainsApp: @Sendable (URL) -> Bool = DownloadsReviewer.zipListsApp

    static let installers: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "img", "exe", "msi", "deb", "rpm", "appimage", "apk", "ipa"]
    static let unfinished: Set<String> = ["crdownload", "part", "download", "opdownload"]
    static let archives: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]
    static let kept: [String: (kind: String, extensions: Set<String>)] = [
        "photo": ("A photo", ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp", "dng", "raw", "cr2", "cr3", "nef", "arw", "orf", "rw2", "svg"]),
        "video": ("A video", ["mov", "mp4", "m4v", "avi", "mkv", "3gp"]),
        "audio": ("A recording or song", ["m4a", "mp3", "wav", "aif", "aiff", "flac", "caf"]),
        "document": ("A document", ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "rtfd", "csv", "odt", "ods", "odp", "epub", "md"]),
    ]

    func review() async throws -> [DownloadItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .addedToDirectoryDateKey]
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        )
        let siblings = Set(entries.map(\.lastPathComponent))
        var items: [DownloadItem] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory ?? false
            let url = folder.appending(path: entry.lastPathComponent, directoryHint: isDirectory ? .isDirectory : .notDirectory)
            let size = isDirectory
                ? try await DiskScanner().scan(url).root.size
                : Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            let origin = DownloadOrigin.read(url)
            let (verdict, reason) = Self.verdict(
                name: url.lastPathComponent, isDirectory: isDirectory, isPackage: values?.isPackage ?? false,
                origin: origin, siblings: siblings, zipContainsApp: { zipContainsApp(url) }
            )
            let source = origin.isEmail ? (origin.agent ?? origin.host) : (origin.host ?? origin.agent)
            items.append(DownloadItem(url: url, isDirectory: isDirectory, size: size, added: values?.addedToDirectoryDate, source: source, verdict: verdict, reason: reason))
        }
        return items.sorted { ($0.verdict.rawValue, -$0.size) < ($1.verdict.rawValue, -$1.size) }
    }

    /// Decides what to do with one item. Anything personal or from email is kept, even an installer.
    static func verdict(
        name: String, isDirectory: Bool, isPackage: Bool, origin: DownloadOrigin,
        siblings: Set<String>, zipContainsApp: () -> Bool
    ) -> (DownloadItem.Verdict, String) {
        let ext = (name as NSString).pathExtension.lowercased()
        if origin.isEmail {
            return (.keep, "Saved from an email, so it's kept.")
        }
        if let kind = kept.values.first(where: { $0.extensions.contains(ext) }) {
            return (.keep, "\(kind.kind), kept since it may not be easy to get again.")
        }
        if unfinished.contains(ext) {
            return (.redownloadable, "An unfinished download.")
        }
        if ext == "app" && isPackage {
            return (.redownloadable, "An app you can download again. If you use it, move it to Applications instead.")
        }
        if installers.contains(ext) {
            return (.redownloadable, "An installer or disk image. You can download it again if you ever need it.")
        }
        if archives.contains(ext) {
            // "Foo.tar.gz" unzips to "Foo".
            var base = name
            while archives.contains((base as NSString).pathExtension.lowercased()) {
                base = (base as NSString).deletingPathExtension
            }
            if siblings.contains(base) || siblings.contains(base + ".app") {
                return (.redownloadable, "Already unzipped right next to it.")
            }
            if ext == "zip" && zipContainsApp() {
                return (.redownloadable, "A zipped app you can download again.")
            }
            return (.unsure, "An archive. Check what's inside before deleting it.")
        }
        if isDirectory {
            return (.unsure, "A folder. Check what's inside before deleting it.")
        }
        return (.unsure, "Not sure what this is.")
    }

    static func zipListsApp(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zipinfo")
        process.arguments = ["-1", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        // Read before waiting, so a long listing can't fill the pipe and stall zipinfo.
        let listing = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return listing.split(separator: "\n").contains { $0.contains(".app/Contents/") && !$0.hasPrefix("__MACOSX") }
    }
}
