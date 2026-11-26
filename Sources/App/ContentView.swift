import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.section) {
                Label("Overview", systemImage: "internaldrive").tag(AppModel.Section.overview)
                Label("Explore", systemImage: "folder").tag(AppModel.Section.explore)
                // The tag goes last: applied after it, .badge hides it and the row can't be selected.
                Label("Recommendations", systemImage: "sparkles")
                    .badge(model.recommendations.count)
                    .tag(AppModel.Section.recommendations)
                Label("Downloads", systemImage: "arrow.down.circle").tag(AppModel.Section.downloads)
                Label("Trash", systemImage: "trash")
                    .badge(trashBadge)
                    .tag(AppModel.Section.trash)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if let progress = model.progress {
                    ScanBanner(progress: progress)
                    Divider()
                }
                switch model.section ?? .overview {
                case .overview: OverviewView()
                case .explore: ExploreView()
                case .recommendations: RecommendationsView()
                case .downloads: DownloadsView()
                case .trash: TrashView()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Scan", selection: $model.target) {
                        Text("Home Folder").tag(AppModel.ScanTarget.home)
                        Text("Whole Disk").tag(AppModel.ScanTarget.wholeDisk)
                        if case .folder(let url) = model.target {
                            Text(url.lastPathComponent).tag(model.target)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Choose Folder…") { model.chooseFolder() }
                } label: {
                    Label(model.targetName, systemImage: "scope")
                        .labelStyle(.titleAndIcon)
                }
                .help("What to scan")
                .disabled(model.isScanning)

                if model.isScanning {
                    Button("Stop", systemImage: "stop.fill") { model.cancelScan() }
                        .labelStyle(.titleAndIcon)
                } else if let scan = model.scan {
                    Button("Scan Again", systemImage: "arrow.clockwise") { model.startScan() }
                        .labelStyle(.titleAndIcon)
                        .help("Last scanned \(scan.finished.formatted(.relative(presentation: .numeric)))")
                } else {
                    Button("Scan", systemImage: "arrow.clockwise") { model.startScan() }
                        .labelStyle(.titleAndIcon)
                        .help("Scan \(model.targetName)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
            // Space frees up when the Trash is emptied, often in Finder, so recheck on return.
            model.refreshVolumes()
            model.refreshTrash()
        }
        .confirmationDialog("Empty the Trash?", isPresented: $model.confirmingEmptyTrash) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            if let trash = model.trash, trash.isReadable {
                Text("This permanently erases \(trash.itemCount.formatted()) \(trash.itemCount == 1 ? "item" : "items") (\(trash.size.bytes)). You can't undo it.")
            } else {
                Text("This permanently erases everything in the Trash. You can't undo it.")
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(model.problem ?? "")
        }
    }
}

extension ContentView {
    /// The Trash's size beside its sidebar row, when there's something in it.
    private var trashBadge: Text? {
        guard let trash = model.trash, trash.isReadable, trash.size > 0 else { return nil }
        return Text(trash.size.bytes)
    }
}

private struct ScanBanner: View {
    @Environment(AppModel.self) private var model
    var progress: ScanProgress.Snapshot

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Scanning: \(progress.files.formatted()) files, \(progress.bytes.bytes)")
                .monospacedDigit()
            if model.scanStalled {
                Label("Waiting. If macOS is asking for permission, answer the prompt to continue.", systemImage: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Text(progress.folder.abbreviatedPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Stop") { model.cancelScan() }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
