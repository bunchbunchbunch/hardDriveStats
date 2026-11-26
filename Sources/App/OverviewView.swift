import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !model.hasFullDiskAccess {
                    FullDiskAccessCard()
                }
                if let disk = model.startupVolume {
                    StartupDisk(volume: disk)
                }
                if let trash = model.trash, trash.isReadable, trash.size > 0 {
                    TrashSummary(trash: trash)
                }
                let others = model.volumes.filter { !$0.isStartup }
                if !others.isEmpty {
                    OtherVolumes(volumes: others)
                }
                UsageHistory(history: model.history)
                if let scan = model.scan {
                    Reclaimable(recommendations: model.recommendations)
                    LargestItems(root: scan.root)
                } else if !model.isScanning {
                    ScanPrompt()
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FullDiskAccessCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Give Drive Stats Full Disk Access").font(.headline)
                Text("Without it, macOS asks for permission folder by folder during a scan, and the scan waits on each answer. Some folders, like Mail and Safari, can't be measured at all. Turn on Drive Stats under Privacy & Security ▸ Full Disk Access, then reopen it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.25)))
    }
}

private struct StartupDisk: View {
    var volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(volume.name).font(.title2.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(volume.available.bytes).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                Text("available of \(volume.total.bytes)").font(.title3).foregroundStyle(.secondary)
            }
            CapacityBar(volume: volume)
            HStack(spacing: 20) {
                LegendDot(style: AnyShapeStyle(Color.accentColor), label: "Used", value: volume.used.bytes)
                LegendDot(style: AnyShapeStyle(Color.accentColor.opacity(0.4)), label: "Purgeable", value: volume.purgeable.bytes)
                LegendDot(style: AnyShapeStyle(.quaternary), label: "Free", value: volume.free.bytes)
            }
            if volume.purgeable > 0 {
                Text("macOS clears purgeable space, such as local snapshots and iCloud copies, on its own when it needs room. It counts as available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TrashSummary: View {
    @Environment(AppModel.self) private var model
    var trash: TrashInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.title3)
                .foregroundStyle(.secondary)
            (Text("\(trash.size.bytes) in the Trash").fontWeight(.semibold)
                + Text(" across \(trash.itemCount.formatted()) \(trash.itemCount == 1 ? "item" : "items"). It uses space until you empty it.")
                .foregroundStyle(.secondary))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Review") { model.section = .trash }
            EmptyTrashButton()
        }
        .font(.callout)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct OtherVolumes: View {
    var volumes: [VolumeInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other disks").font(.headline)
            ForEach(volumes) { volume in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(volume.name)
                        Spacer()
                        Text("\(volume.available.bytes) available of \(volume.total.bytes)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                    CapacityBar(volume: volume, height: 8)
                }
            }
        }
    }
}

private struct UsageHistory: View {
    var history: [DiskSnapshot]
    @State private var hovered: Date?

    private var hoveredSnapshot: DiskSnapshot? {
        guard let hovered else { return nil }
        return history.min { abs($0.date.timeIntervalSince(hovered)) < abs($1.date.timeIntervalSince(hovered)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Space used over time").font(.headline)
                Spacer()
                if let change { Text(change).font(.callout).foregroundStyle(.secondary) }
            }
            if history.count < 2 {
                Text("Drive Stats records how full your startup disk is, at most once an hour, whenever it's open. Check back later to see the trend.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                chart.frame(height: 180)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(history, id: \.date) { snap in
                LineMark(x: .value("Date", snap.date), y: .value("Used", Double(snap.used) / 1e9))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.accentColor)
            }
            if let snap = hoveredSnapshot {
                RuleMark(x: .value("Date", snap.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Date", snap.date), y: .value("Used", Double(snap.used) / 1e9))
                    .symbolSize(70)
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snap.used.bytes + " used").font(.callout.weight(.semibold)).monospacedDigit()
                            Text(snap.date, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let gb = value.as(Double.self) { Text("\(gb, format: .number.precision(.fractionLength(0...1))) GB") } }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $hovered)
    }

    /// How much usage changed over the last week, or since the first snapshot if newer.
    private var change: String? {
        guard let last = history.last, history.count > 1 else { return nil }
        let weekAgo = last.date.addingTimeInterval(-7 * 86_400)
        let base: DiskSnapshot
        let since: String
        if let older = history.last(where: { $0.date <= weekAgo }) {
            (base, since) = (older, "in the last 7 days")
        } else {
            (base, since) = (history[0], "since \(history[0].date.formatted(.dateTime.month().day()))")
        }
        let delta = last.used - base.used
        if abs(delta) < 100_000_000 { return "About the same \(since)" }
        return "\(delta > 0 ? "Up" : "Down") \(abs(delta).bytes) \(since)"
    }
}

private struct Reclaimable: View {
    @Environment(AppModel.self) private var model
    var recommendations: [Recommendation]

    var body: some View {
        let total = recommendations.reduce(0) { $0 + $1.size }
        VStack(alignment: .leading, spacing: 10) {
            Text("Space you could free").font(.headline)
            if recommendations.isEmpty {
                Text("Nothing obvious to delete turned up in this scan.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(total.bytes).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    Text("across \(recommendations.count) suggestions").foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    ForEach(Safety.allCases, id: \.self) { safety in
                        let size = recommendations.filter { $0.safety == safety }.reduce(0) { $0 + $1.size }
                        if size > 0 {
                            Label {
                                Text("\(safety.title): ").foregroundStyle(.secondary) + Text(size.bytes).monospacedDigit()
                            } icon: {
                                Image(systemName: safety.symbol).foregroundStyle(safety.tint)
                            }
                            .font(.callout)
                        }
                    }
                }
                Button("Review Recommendations") { model.section = .recommendations }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct LargestItems: View {
    @Environment(AppModel.self) private var model
    var root: FileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Largest in \(root.url.displayName)").font(.headline)
                Spacer()
                Text("\(root.size.bytes), \(root.fileCount.formatted()) files")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(root.children.prefix(8)) { item in
                Button {
                    model.explore(item.isDirectory ? item.url : root.url)
                } label: {
                    HStack(spacing: 12) {
                        Text(item.name).lineLimit(1).frame(width: 220, alignment: .leading)
                        SizeBar(fraction: Double(item.size) / Double(max(1, root.size)))
                        Text(item.size.bytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ScanPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's using the space?").font(.headline)
            Text("Scan your \(model.targetName.lowercased()) to see the biggest folders and get suggestions for what to delete.")
                .foregroundStyle(.secondary)
            Button("Scan \(model.targetName)") { model.startScan() }
                .buttonStyle(.borderedProminent)
        }
    }
}
