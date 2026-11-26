import SwiftUI

struct RecommendationsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var confirming = false

    var body: some View {
        if let scan = model.scan {
            VStack(spacing: 0) {
                if !scan.unreadable.isEmpty {
                    FullDiskAccessNotice(count: scan.unreadable.count)
                    Divider()
                }
                if model.recommendations.isEmpty {
                    ContentUnavailableView(
                        "Nothing to suggest",
                        systemImage: "checkmark.circle",
                        description: Text("No caches, build folders, or old files over 50 MB turned up in \(scan.root.url.displayName).")
                    )
                } else {
                    list
                    Divider()
                    footer
                }
            }
            .confirmationDialog(
                "Move \(selected.count) \(selected.count == 1 ? "item" : "items") (\(selectedSize.bytes)) to the Trash?",
                isPresented: $confirming
            ) {
                Button("Move to Trash", role: .destructive) {
                    model.moveToTrash(selected.map(\.url))
                    selection.removeAll()
                }
            } message: {
                Text("You can put them back from the Trash. The space is freed when you empty the Trash.")
            }
        } else {
            NoScanView()
        }
    }

    private var selected: [Recommendation] {
        model.recommendations.filter { selection.contains($0.id) }
    }

    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }

    private var list: some View {
        List {
            ForEach(Safety.allCases, id: \.self) { safety in
                let recs = model.recommendations.filter { $0.safety == safety }
                if !recs.isEmpty {
                    Section {
                        ForEach(recs) { rec in
                            RecommendationRow(rec: rec, isSelected: Binding(
                                get: { selection.contains(rec.id) },
                                set: { if $0 { selection.insert(rec.id) } else { selection.remove(rec.id) } }
                            ))
                        }
                    } header: {
                        SafetyHeader(safety: safety, total: recs.reduce(0) { $0 + $1.size })
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if selection.isEmpty {
                Text("Select items to move them to the Trash.").foregroundStyle(.secondary)
            } else {
                Text("\(selected.count) selected, \(selectedSize.bytes)").monospacedDigit()
            }
            Spacer()
            Button("Scan Again", systemImage: "arrow.clockwise") { model.startScan() }
                .disabled(model.isScanning)
            Button("Select All Safe") {
                selection.formUnion(model.recommendations.filter { $0.safety == .safe && $0.canTrash }.map(\.id))
            }
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

private struct SafetyHeader: View {
    var safety: Safety
    var total: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(safety.title, systemImage: safety.symbol)
                    .labelStyle(TintedIconLabelStyle(tint: safety.tint))
                    .font(.headline)
                Spacer()
                Text(total.bytes).font(.headline).monospacedDigit()
            }
            Text(safety.detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title.foregroundStyle(.primary)
        }
    }
}

private struct RecommendationRow: View {
    @Environment(AppModel.self) private var model
    var rec: Recommendation
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Select", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!rec.canTrash)
                .help(rec.canTrash ? "Select to move to the Trash" : "Free this space the way the note describes")
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.title).font(.body.weight(.semibold))
                Text(rec.url.abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(LocalizedStringKey(rec.reason))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let used = rec.lastUsed {
                    Text("Last used \(used.formatted(.relative(presentation: .numeric)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                Text(rec.size.bytes).font(.body.weight(.semibold)).monospacedDigit()
                Button {
                    model.reveal(rec.url)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if rec.canTrash { isSelected.toggle() } }
    }
}
