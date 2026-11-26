import SwiftUI

/// How much is in the Trash, what's biggest, and a button to empty it.
struct TrashView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if let trash = model.trash, trash.isReadable {
                    Text(trash.size.bytes).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    Text(trash.itemCount == 0
                        ? "The Trash is empty"
                        : "in \(trash.itemCount.formatted()) \(trash.itemCount == 1 ? "item" : "items"), still using space until you empty it")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Trash").font(.title2.weight(.semibold))
                    Text(model.trash == nil ? "Measuring…" : "Size unknown without Full Disk Access")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open in Finder") { model.openTrashInFinder() }
            EmptyTrashButton()
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if let trash = model.trash {
            if !trash.isReadable {
                ContentUnavailableView {
                    Label("Can't see inside the Trash", systemImage: "lock.fill")
                } description: {
                    Text("macOS only lets apps with Full Disk Access look in the Trash. You can still empty it.")
                } actions: {
                    Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                }
            } else if trash.itemCount == 0 {
                ContentUnavailableView(
                    "The Trash is empty",
                    systemImage: "trash",
                    description: Text("Files you delete wait here, still using space, until you empty the Trash.")
                )
            } else {
                List {
                    ForEach(trash.items) { item in
                        ItemRow(item: item, parentSize: trash.size, opensFolders: false)
                            .contextMenu {
                                Button("Show in Finder") { model.reveal(item.url) }
                            }
                    }
                    if trash.smallItemCount > 0 {
                        HStack {
                            Text("\(trash.smallItemCount.formatted()) smaller \(trash.smallItemCount == 1 ? "item" : "items") under 1 MB")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(trash.smallItemBytes.bytes)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Asks to confirm, then empties the Trash. Shows progress while Finder works.
struct EmptyTrashButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(role: .destructive) {
            model.confirmingEmptyTrash = true
        } label: {
            if model.isEmptyingTrash {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Emptying…")
                }
            } else {
                Text("Empty Trash…")
            }
        }
        .disabled(model.isEmptyingTrash || isKnownEmpty)
    }

    private var isKnownEmpty: Bool {
        guard let trash = model.trash, trash.isReadable else { return false }
        return trash.itemCount == 0
    }
}
