import SwiftUI

@main
struct DriveStatsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Drive Stats", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
                #if DEBUG
                .task { await SnapshotRun.runIfRequested(model) }
                #endif
        }
        .defaultSize(width: 1040, height: 720)
    }
}
