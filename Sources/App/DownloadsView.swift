import SwiftUI

/// Clears out Downloads: things easy to download again come pre-selected; photos,
/// documents, and email attachments are never selected for you.
struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let items = model.downloads {
                if items.isEmpty {
                    ContentUnavailableView("Downloads is empty", systemImage: "arrow.down.circle")
                } else {
                    list(items)
                    Divider()
                    footer
                }
            } else if let problem = model.downloadsProblem {
                ContentUnavailableView {
                    Label("Can't read Downloads", systemImage: "lock.fill")
                } description: {
                    Text(problem)
                } actions: {
                    Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selection = Self.easyToGetAgain(model.downloads)
            model.reviewDownloads()
        }
        .onChange(of: model.downloads) { _, items in selection = Self.easyToGetAgain(items) }
        .confirmationDialog(
            "Move \(selected.count) \(selected.count == 1 ? "item" : "items") (\(selectedSize.bytes)) to the Trash?",
            isPresented: $confirming
        ) {
            Button("Move to Trash", role: .destructive) {
                model.moveToTrash(selected.map(\.url))
            }
        } message: {
            Text("You can put them back from the Trash until you empty it.")
        }
    }

    private static func easyToGetAgain(_ items: [DownloadItem]?) -> Set<String> {
        Set((items ?? []).filter { $0.verdict == .redownloadable }.map(\.id))
    }

    private var selected: [DownloadItem] {
        (model.downloads ?? []).filter { selection.contains($0.id) }
    }

    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }

    private var header: some View {
        let easy = (model.downloads ?? []).filter { $0.verdict == .redownloadable }
        return HStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clean up Downloads").font(.title2.weight(.semibold))
                Text(easy.isEmpty
                    ? "Nothing here looks easy to download again. Photos, documents, and email attachments stay."
                    : "\(easy.reduce(0) { $0 + $1.size }.bytes) in \(easy.count) \(easy.count == 1 ? "item" : "items") you could download again. Photos, documents, and email attachments stay.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Check Again", systemImage: "arrow.clockwise") { model.reviewDownloads() }
                .disabled(model.isReviewingDownloads)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func list(_ items: [DownloadItem]) -> some View {
        List {
            ForEach(DownloadItem.Verdict.allCases, id: \.self) { verdict in
                let group = items.filter { $0.verdict == verdict }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { item in
                            DownloadRow(item: item, isSelected: Binding(
                                get: { selection.contains(item.id) },
                                set: { if $0 { selection.insert(item.id) } else { selection.remove(item.id) } }
                            ))
                        }
                    } header: {
                        VerdictHeader(verdict: verdict, total: group.reduce(0) { $0 + $1.size })
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(selection.isEmpty ? "Nothing selected." : "\(selected.count) selected, \(selectedSize.bytes)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Select Easy to Download Again") { selection = Self.easyToGetAgain(model.downloads) }
            Button("Clear") { selection.removeAll() }
                .disabled(selection.isEmpty)
            Button("Move to Trash…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

extension DownloadItem.Verdict {
    var title: String {
        switch self {
        case .redownloadable: "Easy to download again"
        case .unsure: "Not sure"
        case .keep: "Keeping"
        }
    }

    var detail: String {
        switch self {
        case .redownloadable: "Installers, apps, and leftovers a website will give you again. Selected for you."
        case .unsure: "Archives, folders, and files Drive Stats can't place. Look before deleting."
        case .keep: "Photos, videos, documents, and anything from email. Never selected for you."
        }
    }

    var symbol: String {
        switch self {
        case .redownloadable: "arrow.down.circle.fill"
        case .unsure: "questionmark.circle.fill"
        case .keep: "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .redownloadable: .blue
        case .unsure: .orange
        case .keep: .green
        }
    }
}

private struct VerdictHeader: View {
    var verdict: DownloadItem.Verdict
    var total: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: verdict.symbol).foregroundStyle(verdict.tint)
                Text(verdict.title).foregroundStyle(.primary)
                Spacer()
                Text(total.bytes).monospacedDigit()
            }
            .font(.headline)
            Text(verdict.detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    var item: DownloadItem
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Select", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(item.reason).font(.callout)
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.size.bytes)
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Button {
                model.reveal(item.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }

    private var details: String {
        var parts: [String] = []
        if let source = item.source { parts.append("From \(source)") }
        if let added = item.added { parts.append("added \(added.formatted(.relative(presentation: .numeric)))") }
        return parts.joined(separator: ", ")
    }
}
