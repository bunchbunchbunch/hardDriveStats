import CoreServices
import Foundation

/// How careful to be before deleting a suggestion.
enum Safety: Int, CaseIterable, Comparable, Sendable {
    case safe, rebuildable, review

    static func < (a: Safety, b: Safety) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .safe: "Safe to delete"
        case .rebuildable: "Rebuildable"
        case .review: "Review first"
        }
    }

    var detail: String {
        switch self {
        case .safe: "Caches and leftovers that apps recreate on their own."
        case .rebuildable: "Build output and downloaded dependencies. A build or install command brings them back."
        case .review: "Your own files and app data. Look at each one before deleting it."
        }
    }
}

/// A file or folder worth deleting, and why.
struct Recommendation: Identifiable, Hashable, Sendable {
    var url: URL
    var title: String
    /// Markdown, so commands can be shown as `code`.
    var reason: String
    var safety: Safety
    var size: Int64
    var lastUsed: Date?
    /// False when the space is better reclaimed another way, which `reason` explains.
    var canTrash = true

    var id: String { url.path }
}

/// Turns a scan into a list of things to delete.
struct Recommender: Sendable {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var now = Date()
    /// Anything smaller isn't worth suggesting.
    var minimumSize: Int64 = 50_000_000
    /// Files this big get suggested when they haven't been used in `staleDays`.
    var largeFileSize: Int64 = 500_000_000
    var staleDays = 90
    var unusedAppDays = 180
    /// When an app was last opened. Spotlight by default; tests substitute their own.
    var appLastOpened: @Sendable (URL) -> Date? = Recommender.spotlightLastUsed

    func recommendations(for root: FileNode) -> [Recommendation] {
        // Earlier rules win when two suggest the same path.
        var found = knownLocations(in: root)
        // Only look at loose files where they're yours: the home folder, or another disk.
        // A scan of /System or /Library must not offer macOS's own disk images.
        let isUserLocation = root.url.path.isWithin(home.path) || root.url.path.isWithin("/Volumes")
        if let userArea = root.node(at: home) ?? (isUserLocation ? root : nil) {
            found += buildFolders(in: userArea)
            found += largeFilesAndInstallers(in: userArea)
        }
        found += oldDownloads(in: root)
        found += unusedApps(in: root)
        return removingOverlaps(found).sorted { $0.size > $1.size }
    }

    // MARK: Known space hogs

    private struct KnownSpot {
        var path: String
        var title: String
        var reason: String
        var safety: Safety
        /// Suggest each big item inside, not the folder as a whole.
        var eachItem = false
        var canTrash = true
    }

    private static let knownSpots = [
        KnownSpot(path: ".Trash", title: "Trash", reason: "Files in the Trash use space until you empty it. Empty it from the Trash section.", safety: .safe, canTrash: false),
        KnownSpot(path: "Library/Caches", title: "Cache", reason: "Apps rebuild their caches as needed. Quit the app first.", safety: .safe, eachItem: true),
        KnownSpot(path: "Library/Logs", title: "Logs", reason: "Old log files and crash reports.", safety: .safe),
        KnownSpot(path: "Library/Developer/Xcode/DerivedData", title: "Xcode DerivedData", reason: "Build intermediates. Xcode recreates them on the next build.", safety: .safe),
        KnownSpot(path: "Library/Developer/Xcode/iOS DeviceSupport", title: "iOS device support", reason: "Debug symbols for one iOS version. Xcode copies them again when a device on that version connects.", safety: .safe, eachItem: true),
        KnownSpot(path: "Library/Developer/Xcode/watchOS DeviceSupport", title: "watchOS device support", reason: "Debug symbols for one watchOS version. Xcode copies them again when a watch on that version connects.", safety: .safe, eachItem: true),
        KnownSpot(path: "Library/Developer/Xcode/UserData/Previews", title: "SwiftUI previews", reason: "Preview builds. Xcode recreates them.", safety: .safe),
        KnownSpot(path: "Library/Developer/CoreSimulator/Caches", title: "Simulator caches", reason: "Simulator caches. Xcode recreates them.", safety: .safe),
        KnownSpot(path: "Library/Developer/CoreSimulator/Devices", title: "Simulator devices", reason: "Simulators and their app data. Remove ones you don't use with `xcrun simctl delete unavailable` or in Xcode's Devices and Simulators window.", safety: .review, canTrash: false),
        KnownSpot(path: "Library/Developer/Xcode/Archives", title: "Xcode archives", reason: "Archived builds. Keep the ones you need to read crash reports from shipped versions.", safety: .review, eachItem: true),
        KnownSpot(path: "Library/Application Support/MobileSync/Backup", title: "iPhone or iPad backup", reason: "A device backup. Delete backups of devices you no longer have.", safety: .review, eachItem: true),
        KnownSpot(path: "Library/Containers/com.docker.docker/Data/vms", title: "Docker disk image", reason: "Docker's images and containers. Reclaim space with `docker system prune -a` rather than deleting the file.", safety: .review, canTrash: false),
        KnownSpot(path: ".npm/_cacache", title: "npm cache", reason: "Downloaded packages. npm fetches them again when needed.", safety: .safe),
        KnownSpot(path: ".cache", title: "Tool cache", reason: "A command-line tool's download or build cache. The tool refetches it when needed.", safety: .safe, eachItem: true),
        KnownSpot(path: ".gradle/caches", title: "Gradle cache", reason: "Downloaded dependencies and build caches. Gradle refetches them.", safety: .safe),
        KnownSpot(path: ".m2/repository", title: "Maven repository", reason: "Downloaded dependencies. Maven refetches them.", safety: .safe),
        KnownSpot(path: ".cargo/registry", title: "Cargo registry", reason: "Downloaded crates. Cargo refetches them.", safety: .safe),
        KnownSpot(path: "go/pkg/mod", title: "Go module cache", reason: "Downloaded modules. Clear it with `go clean -modcache`; the files are read-only, so the Trash can't take them.", safety: .safe, canTrash: false),
        KnownSpot(path: ".cocoapods/repos", title: "CocoaPods specs", reason: "The CocoaPods spec repo. `pod install` downloads it again.", safety: .safe),
        KnownSpot(path: "Library/pnpm/store", title: "pnpm store", reason: "Downloaded packages. pnpm refetches them.", safety: .safe),
        KnownSpot(path: ".bun/install/cache", title: "Bun cache", reason: "Downloaded packages. Bun refetches them.", safety: .safe),
        KnownSpot(path: ".ollama/models", title: "Ollama models", reason: "Local AI models. Remove ones you don't use with `ollama rm <model>`.", safety: .review, canTrash: false),
    ]

    private func knownLocations(in root: FileNode) -> [Recommendation] {
        Self.knownSpots.flatMap { spot -> [Recommendation] in
            guard let node = root.node(at: home.appending(path: spot.path)) else { return [] }
            guard spot.eachItem else {
                guard node.size >= minimumSize else { return [] }
                return [recommend(node, spot.title, spot.reason, spot.safety, canTrash: spot.canTrash)]
            }
            return node.children.filter { $0.size >= minimumSize }.map { item in
                // Apple's own caches are usually fine to clear, but macOS rebuilds some at a cost.
                item.name.hasPrefix("com.apple.")
                    ? recommend(item, "\(spot.title): \(item.name)", "A macOS cache. Usually safe to clear, but macOS may run slowly while it rebuilds.", .review)
                    : recommend(item, "\(spot.title): \(item.name)", spot.reason, spot.safety, canTrash: spot.canTrash)
            }
        }
    }

    // MARK: Project build folders

    private struct BuildFolder {
        var names: Set<String>
        /// Files that show this really is a build folder, relative to it. Any one is enough.
        var markers: [String]
        var title: String
        var reason: String
        var safety = Safety.rebuildable
    }

    private static let buildFolderKinds = [
        BuildFolder(names: ["node_modules"], markers: ["../package.json"], title: "node_modules", reason: "JavaScript packages. `npm install` (or yarn, pnpm) downloads them again."),
        BuildFolder(names: [".build"], markers: ["../Package.swift"], title: "Swift build folder", reason: "`swift build` recreates it."),
        BuildFolder(names: ["target"], markers: ["../Cargo.toml"], title: "Rust build folder", reason: "`cargo build` recreates it."),
        BuildFolder(names: ["Pods"], markers: ["../Podfile"], title: "CocoaPods", reason: "`pod install` downloads them again."),
        BuildFolder(names: [".next"], markers: ["../package.json"], title: "Next.js build", reason: "`next build` recreates it."),
        BuildFolder(names: [".gradle"], markers: ["../settings.gradle", "../settings.gradle.kts", "../build.gradle", "../build.gradle.kts"], title: "Gradle project cache", reason: "Gradle recreates it on the next build."),
        BuildFolder(names: [".venv", "venv"], markers: ["pyvenv.cfg"], title: "Python virtual environment", reason: "Recreate it with `python -m venv` and reinstall the requirements."),
        BuildFolder(names: ["DerivedData"], markers: [], title: "Xcode DerivedData", reason: "Build intermediates. Xcode recreates them on the next build.", safety: .safe),
    ]

    private func buildFolders(in area: FileNode) -> [Recommendation] {
        var found: [Recommendation] = []
        walk(area) { node in
            guard node.isDirectory else { return false }
            if let kind = Self.buildFolderKinds.first(where: { $0.names.contains(node.name) }),
               kind.markers.isEmpty || kind.markers.contains(where: { exists(node.url.path + "/" + $0) }) {
                if node.size >= minimumSize {
                    let project = node.url.deletingLastPathComponent().lastPathComponent
                    found.append(recommend(node, "\(kind.title) in \(project)", kind.reason, kind.safety))
                }
                return false
            }
            // Hidden folders hold tools and editor extensions, whose build folders aren't yours to delete.
            return !node.name.hasPrefix(".")
        }
        return found
    }

    // MARK: Big, old, and leftover files

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    private func largeFilesAndInstallers(in area: FileNode) -> [Recommendation] {
        var found: [Recommendation] = []
        walk(area) { node in
            guard !node.isDirectory else { return true }
            if Self.installerExtensions.contains(node.url.pathExtension.lowercased()) {
                found.append(recommend(node, node.name, "An installer or disk image. You don't need it once the app is installed.", .review))
            } else if node.size >= largeFileSize && isStale(node.lastUsed, days: staleDays) {
                found.append(recommend(node, node.name, "A large file you haven't opened in over \(staleDays / 30) months.", .review))
            }
            return false
        }
        return found
    }

    private func oldDownloads(in root: FileNode) -> [Recommendation] {
        guard let downloads = root.node(at: home.appending(path: "Downloads")) else { return [] }
        return downloads.children
            .filter { $0.size >= minimumSize && isStale($0.lastUsed, days: staleDays) }
            .map { recommend($0, $0.name, "In Downloads and untouched for over \(staleDays / 30) months.", .review) }
    }

    private func unusedApps(in root: FileNode) -> [Recommendation] {
        let folders = [URL(filePath: "/Applications"), home.appending(path: "Applications")]
        var found: [Recommendation] = []
        for folder in folders.compactMap({ root.node(at: $0) }) {
            for app in folder.children where app.isPackage && app.url.pathExtension == "app" && app.size >= minimumSize {
                guard let opened = appLastOpened(app.url), isStale(opened, days: unusedAppDays) else { continue }
                let name = app.url.deletingPathExtension().lastPathComponent
                var rec = recommend(app, name, "An app you haven't opened in over \(unusedAppDays / 30) months.", .review)
                rec.lastUsed = opened
                found.append(rec)
            }
        }
        return found
    }

    static func spotlightLastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Helpers

    private func recommend(_ node: FileNode, _ title: String, _ reason: String, _ safety: Safety, canTrash: Bool = true) -> Recommendation {
        Recommendation(url: node.url, title: title, reason: reason, safety: safety, size: node.size, lastUsed: node.lastUsed, canTrash: canTrash)
    }

    /// Visits everything beneath `node`, descending wherever `visit` returns true. Never goes
    /// into ~/Library (app data) or inside packages such as apps and photo libraries.
    private func walk(_ node: FileNode, _ visit: (FileNode) -> Bool) {
        let library = home.appending(path: "Library").path
        for child in node.children where !child.url.path.isWithin(library) {
            if visit(child) && child.isDirectory && !child.isPackage { walk(child, visit) }
        }
    }

    private func isStale(_ date: Date?, days: Int) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) >= Double(days) * 86_400
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    /// Drops repeats and anything inside another suggestion, keeping the outermost.
    private func removingOverlaps(_ recs: [Recommendation]) -> [Recommendation] {
        var seen = Set<String>()
        let unique = recs.filter { seen.insert($0.url.path).inserted }
        var kept: [Recommendation] = []
        for rec in unique.sorted(by: { $0.url.path.count < $1.url.path.count })
        where !kept.contains(where: { rec.url.path.isWithin($0.url.path) }) {
            kept.append(rec)
        }
        return kept
    }
}
