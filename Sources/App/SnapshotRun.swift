#if DEBUG
import AppKit

/// Checks the UI without Screen Recording permission. Launched with DRIVESTATS_SNAPSHOTS=<folder>,
/// the app scans DRIVESTATS_SCAN (or the home folder), saves a PNG of each section, and quits.
/// The window draws itself into the image, so nothing captures the screen.
@MainActor
enum SnapshotRun {
    static func runIfRequested(_ model: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["DRIVESTATS_SNAPSHOTS"].map({ URL(filePath: $0) }) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let path = env["DRIVESTATS_SCAN"] { model.target = .folder(URL(filePath: path)) }

        await settle()
        save("1-overview-before-scan", in: folder)
        model.startScan()
        await settle()
        save("2-scanning", in: folder)
        while model.isScanning { try? await Task.sleep(for: .milliseconds(250)) }

        let sections: [(String, AppModel.Section)] = [
            ("3-overview", .overview), ("4-explore", .explore), ("5-recommendations", .recommendations),
            ("7-trash", .trash), ("9-downloads", .downloads),
        ]
        for (name, section) in sections {
            model.section = section
            await settle()
            save(name, in: folder)
        }
        model.section = .overview
        await settle()
        save("8-overview-top", in: folder)
        if let big = model.scan?.root.children.first(where: \.isDirectory) {
            model.explore(big.url)
            await settle()
            save("6-explore-drilled", in: folder)
        }
        await probeSidebar(model, into: folder.appending(path: "sidebar-probe.txt"))
        NSApp.terminate(nil)
    }

    /// Selects each sidebar row through its table, as a click does, and records which section opens.
    /// (Synthetic mouse clicks don't work here: an app opened over ssh never becomes active.)
    private static func probeSidebar(_ model: AppModel, into file: URL) async {
        var log: [String] = []
        defer { try? log.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8) }
        guard let window = NSApp.windows.first(where: \.isVisible), let root = window.contentView?.superview else {
            log.append("no window")
            return
        }
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        let views = descendants(root)
        let left = views.filter { $0.convert($0.bounds, to: nil).minX < 200 && $0.bounds.width > 20 }
        log.append("views in the sidebar area: " + Set(left.map { String(describing: type(of: $0)) }).sorted().joined(separator: ", "))
        let tables = views.compactMap { $0 as? NSTableView }
        log.append("tables: " + tables.map { "\(type(of: $0)) x=\(Int($0.convert($0.bounds, to: nil).minX)) rows=\($0.numberOfRows)" }.joined(separator: "; "))
        guard let sidebar = tables.min(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }) else { return }

        for row in [1, 2, 3, 4, 0] {
            model.section = .overview
            await settle()
            sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            await settle()
            log.append("selected row \(row): section=\(String(describing: model.section))")
        }
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(1200))
    }

    private static func save(_ name: String, in folder: URL) {
        guard let window = NSApp.windows.first(where: \.isVisible),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name).png"))
    }
}
#endif
