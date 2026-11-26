import SwiftUI

extension Int64 {
    var bytes: String { formatted(.byteCount(style: .file)) }
}

extension String {
    var abbreviatedPath: String { (self as NSString).abbreviatingWithTildeInPath }
}

extension URL {
    var abbreviatedPath: String { path.abbreviatedPath }
    /// What Finder calls it, such as "Macintosh HD" for /.
    var displayName: String { FileManager.default.displayName(atPath: path) }
}

/// How much of a whole one item takes, as a thin one-hue bar.
struct SizeBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(fraction > 0 ? 4 : 0, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Used, purgeable, and free space as one segmented bar.
struct CapacityBar: View {
    var volume: VolumeInfo
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let segments: [(Int64, AnyShapeStyle)] = [
                (volume.used, AnyShapeStyle(Color.accentColor)),
                (volume.purgeable, AnyShapeStyle(Color.accentColor.opacity(0.4))),
                (volume.free, AnyShapeStyle(.quaternary)),
            ].filter { $0.0 > 0 }
            let gaps = CGFloat(max(0, segments.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(segments.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(segments[i].1)
                        .frame(width: max(2, (geo.size.width - gaps) * Double(segments[i].0) / Double(volume.total)))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(volume.used.bytes) used, \(volume.purgeable.bytes) purgeable, \(volume.free.bytes) free")
    }
}

struct LegendDot: View {
    var style: AnyShapeStyle
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(style).frame(width: 9, height: 9)
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

/// Shown where scan results would be, before the first scan.
struct NoScanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isScanning {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("Scanning \(model.targetName)…")
            }
        } else {
            ContentUnavailableView {
                Label("No scan yet", systemImage: "magnifyingglass")
            } description: {
                Text("Scan to see what's using space and what you could delete.")
            } actions: {
                Button("Scan \(model.targetName)") { model.startScan() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Explains why some folders are missing and how to include them.
struct FullDiskAccessNotice: View {
    @Environment(AppModel.self) private var model
    var count: Int

    var body: some View {
        // No fixedSize on the text: beside a list, SwiftUI can measure it at almost no width,
        // and its full wrapped height then pushes the whole view off screen.
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            Text("\(count.formatted()) \(count == 1 ? "folder" : "folders") couldn't be read, so sizes may be low. Give Drive Stats Full Disk Access to include them, then scan again.")
                .font(.callout)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
    }
}

extension Safety {
    var symbol: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .rebuildable: "arrow.triangle.2.circlepath"
        case .review: "eye.fill"
        }
    }

    var tint: Color {
        switch self {
        case .safe: .green
        case .rebuildable: .blue
        case .review: .orange
        }
    }
}
