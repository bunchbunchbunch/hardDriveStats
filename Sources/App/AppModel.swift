import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    enum Section: Hashable { case overview, explore, recommendations, downloads, trash }

    enum ScanTarget: Hashable {
        case home, wholeDisk, folder(URL)
    }

    var section: Section? = .overview
    var volumes: [VolumeInfo] = []
    var history: [DiskSnapshot] = []
    var target = ScanTarget.home
    var scan: ScanResult?
    var recommendations: [Recommendation] = []
    /// Live counts while a scan runs; nil otherwise.
    var progress: ScanProgress.Snapshot?
    /// True when a running scan has made no progress for a few seconds, usually because
    /// macOS is waiting on a permission prompt.
    var scanStalled = false
    var hasFullDiskAccess = AppModel.checkFullDiskAccess()
    /// The folder the Explore view shows; nil means the scan's root.
    var explorePath: URL?
    /// An error to show the user.
    var problem: String?
    /// The Trash's contents; nil until first measured.
    var trash: TrashInfo?
    var isEmptyingTrash = false
    /// Shows the "Empty the Trash?" confirmation, which any view can ask for.
    var confirmingEmptyTrash = false
    /// What's in Downloads, sorted by how easy it is to get again; nil until reviewed.
    var downloads: [DownloadItem]?
    /// Why Downloads couldn't be reviewed, if it couldn't.
    var downloadsProblem: String?
    var isReviewingDownloads = false

    private var scanTask: Task<Void, Never>?
    private var trashTask: Task<Void, Never>?
    /// The user's Trash. Debug builds can point it elsewhere with DRIVESTATS_TRASH, for snapshots.
    private let trashFolder: URL = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DRIVESTATS_TRASH"] { return URL(filePath: path) }
        #endif
        return TrashInfo.userTrash
    }()
    /// The Downloads folder. Debug builds can point it elsewhere with DRIVESTATS_DOWNLOADS.
    private let downloadsFolder: URL = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DRIVESTATS_DOWNLOADS"] { return URL(filePath: path) }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    }()
    private let historyStore = HistoryStore.standard

    init() {
        refreshVolumes()
        refreshTrash()
        // Keep recording while the app is open; the store keeps snapshots an hour apart.
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard let self else { return }
                self.refreshVolumes()
            }
        }
    }

    var startupVolume: VolumeInfo? { volumes.first(where: \.isStartup) }
    var isScanning: Bool { progress != nil }

    var targetURL: URL {
        switch target {
        case .home: FileManager.default.homeDirectoryForCurrentUser
        case .wholeDisk: URL(filePath: "/")
        case .folder(let url): url
        }
    }

    var targetName: String {
        switch target {
        case .home: "Home Folder"
        case .wholeDisk: "Whole Disk"
        case .folder(let url): url.lastPathComponent
        }
    }

    func refreshVolumes() {
        volumes = VolumeInfo.mounted()
        guard let disk = startupVolume else { return }
        let snapshot = DiskSnapshot(date: .now, total: disk.total, available: disk.available)
        history = (try? historyStore.record(snapshot)) ?? historyStore.load()
    }

    // MARK: Scanning

    func startScan() {
        guard !isScanning else { return }
        let root = targetURL
        let tracker = ScanProgress()
        progress = tracker.snapshot
        scanTask = Task {
            let poll = Task {
                var lastFiles = -1
                var lastChange = Date.now
                while !Task.isCancelled {
                    let snapshot = tracker.snapshot
                    if snapshot.files != lastFiles {
                        lastFiles = snapshot.files
                        lastChange = .now
                    }
                    progress = snapshot
                    scanStalled = Date.now.timeIntervalSince(lastChange) > 3
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            do {
                let (result, recs) = try await Self.scanAndRecommend(root, tracker)
                scan = result
                recommendations = recs
                explorePath = nil
            } catch is CancellationError {
            } catch {
                problem = error.localizedDescription
            }
            poll.cancel()
            progress = nil
            scanStalled = false
            refreshVolumes()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        target = .folder(url)
        startScan()
    }

    @concurrent
    private nonisolated static func scanAndRecommend(_ root: URL, _ tracker: ScanProgress) async throws -> (ScanResult, [Recommendation]) {
        let result = try await DiskScanner().scan(root, progress: tracker)
        try Task.checkCancellation()
        return (result, Recommender().recommendations(for: result.root))
    }

    // MARK: Acting on results

    func moveToTrash(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                scan?.root.remove(url)
                recommendations.removeAll { $0.url.path.isWithin(url.path) }
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let explorePath, scan?.root.node(at: explorePath) == nil { self.explorePath = nil }
        if !failures.isEmpty {
            problem = "Some items couldn't be moved to the Trash.\n\n" + failures.joined(separator: "\n")
        }
        refreshTrash()
        if downloads != nil { reviewDownloads() }
    }

    // MARK: Downloads

    func reviewDownloads() {
        guard !isReviewingDownloads else { return }
        isReviewingDownloads = true
        let folder = downloadsFolder
        Task {
            do {
                downloads = try await Self.reviewDownloads(in: folder)
                downloadsProblem = nil
            } catch {
                downloads = nil
                downloadsProblem = "macOS didn't let Drive Stats read your Downloads folder. Give it Full Disk Access, or allow Downloads under Privacy & Security ▸ Files & Folders."
            }
            isReviewingDownloads = false
        }
    }

    @concurrent
    private nonisolated static func reviewDownloads(in folder: URL) async throws -> [DownloadItem] {
        try await DownloadsReviewer(folder: folder).review()
    }

    // MARK: Trash

    func refreshTrash() {
        trashTask?.cancel()
        let folder = trashFolder
        trashTask = Task {
            guard let info = try? await Self.measureTrash(folder), !Task.isCancelled else { return }
            trash = info
        }
    }

    @concurrent
    private nonisolated static func measureTrash(_ folder: URL) async throws -> TrashInfo {
        try await TrashInfo.measure(folder)
    }

    /// Asks Finder to empty the Trash, which also handles locked files and the Trash on other disks.
    func emptyTrash() {
        guard !isEmptyingTrash else { return }
        isEmptyingTrash = true
        Task {
            if let failure = await Self.askFinderToEmptyTrash() {
                problem = failure
            } else {
                // The scan's copy of the Trash is now out of date.
                scan?.root.remove(trashFolder)
                recommendations.removeAll { $0.url.path.isWithin(trashFolder.path) }
            }
            isEmptyingTrash = false
            refreshTrash()
            refreshVolumes()
        }
    }

    func openTrashInFinder() {
        NSWorkspace.shared.open(trashFolder)
    }

    /// Runs Finder's "empty trash" and returns a message for the user if it failed.
    @concurrent
    private nonisolated static func askFinderToEmptyTrash() async -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "with timeout of 3600 seconds",
            "-e", "tell application \"Finder\" to empty trash",
            "-e", "end timeout",
        ]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        let status: Int32? = await withCheckedContinuation { done in
            process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { done.resume(returning: nil) }
        }
        guard let status else { return "Couldn't ask Finder to empty the Trash." }
        if status == 0 { return nil }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if message.contains("-1743") {
            return "Drive Stats isn't allowed to control Finder, which it uses to empty the Trash. Turn it on in System Settings ▸ Privacy & Security ▸ Automation, under Drive Stats, then try again."
        }
        return "Finder couldn't empty the Trash.\n\n\(message.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    func refreshAccess() {
        hasFullDiskAccess = Self.checkFullDiskAccess()
    }

    /// Tries a file only Full Disk Access can open. Unlike app containers or Documents,
    /// these never put up a permission prompt; they just fail.
    private static func checkFullDiskAccess() -> Bool {
        let tccDatabase = URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = try? FileHandle(forReadingFrom: tccDatabase) {
            try? handle.close()
            return true
        }
        let safari = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: safari.path)) != nil
    }

    func explore(_ url: URL) {
        explorePath = url
        section = .explore
    }
}
