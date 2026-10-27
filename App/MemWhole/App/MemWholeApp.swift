import SwiftUI

@main
struct MemWholeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // One window: every view reads the same index and search state.
        Window("MemWhole", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
