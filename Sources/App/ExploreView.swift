import SwiftUI

struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingTrash: FileNode?

    var body: some View {
        if let scan = model.scan {
            let folder = model.explorePath.flatMap { scan.root.node(at: $0) } ?? scan.root
            VStack(spacing: 0) {
                Breadcrumbs(root: scan.root, folder: folder)
                Divider()
                if !scan.unreadable.isEmpty {
                    FullDiskAccessNotice(count: scan.unreadable.count)
                    Divider()
                }
                List {
                    ForEach(folder.children) { item in
                        ItemRow(item: item, parentSize: folder.size)
                            .contentShape(Rectangle())
                            .onTapGesture { if item.isDirectory { model.explorePath = item.url } }
                            .contextMenu {
                                Button("Show in Finder") { model.reveal(item.url) }
                                Divider()
                                Button("Move to Trash…") { pendingTrash = item }
                            }
                    }
                    if folder.smallFileCount > 0 {
                        SmallFilesRow(count: folder.smallFileCount, size: folder.smallFileBytes, parentSize: folder.size)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            .confirmationDialog(
                "Move \"\(pendingTrash?.name ?? "")\" to the Trash?",
                isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
                presenting: pendingTrash
            ) { item in
                Button("Move to Trash", role: .destructive) { model.moveToTrash([item.url]) }
            } message: { item in
                Text("It uses \(item.size.bytes). You can put it back from the Trash; the space is freed when you empty the Trash.")
            }
        } else {
            NoScanView()
        }
    }
}

private struct Breadcrumbs: View {
    @Environment(AppModel.self) private var model
    var root: FileNode
    var folder: FileNode

    /// The scan root, then each folder down to the one shown.
    private var trail: [URL] {
        var urls: [URL] = []
        var url = folder.url
        while url.path != root.url.path && url.path.isWithin(root.url.path) {
            urls.insert(url, at: 0)
            url = url.deletingLastPathComponent()
        }
        return [root.url] + urls
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.explorePath = folder.url.deletingLastPathComponent()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Enclosing folder")
            .disabled(folder.url.path == root.url.path)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(trail.enumerated()), id: \.offset) { index, url in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button(url.displayName) { model.explorePath = url }
                            .buttonStyle(.plain)
                            .fontWeight(index == trail.count - 1 ? .semibold : .regular)
                            .foregroundStyle(index == trail.count - 1 ? .primary : .secondary)
                    }
                }
            }
            Spacer()
            Text("\(folder.size.bytes), \(folder.fileCount.formatted()) files")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button {
                model.reveal(folder.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Show in Finder")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct ItemRow: View {
    var item: FileNode
    var parentSize: Int64
    /// Whether clicking a folder opens it, which the chevron advertises.
    var opensFolders = true

    var body: some View {
        let fraction = Double(item.size) / Double(max(1, parentSize))
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            SizeBar(fraction: fraction).frame(width: 140)
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Text(item.size.bytes)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(item.isDirectory && opensFolders ? 1 : 0)
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        var parts: [String] = []
        if item.isDirectory { parts.append("\(item.fileCount.formatted()) \(item.fileCount == 1 ? "file" : "files")") }
        if let used = item.lastUsed {
            parts.append("last used \(used.formatted(.relative(presentation: .numeric)))")
        }
        return parts.joined(separator: ", ")
    }
}

private struct SmallFilesRow: View {
    var count: Int
    var size: Int64
    var parentSize: Int64

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count.formatted()) smaller \(count == 1 ? "file" : "files")").foregroundStyle(.secondary)
                Text("Files under 10 MB directly in this folder").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 16)
            SizeBar(fraction: Double(size) / Double(max(1, parentSize))).frame(width: 140).opacity(0.5)
            Text(Double(size) / Double(max(1, parentSize)), format: .percent.precision(.fractionLength(0)))
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Text(size.bytes)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption).opacity(0)
        }
        .padding(.vertical, 2)
    }
}
