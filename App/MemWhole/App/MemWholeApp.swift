import SwiftUI

@main
struct MemWholeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // One window: every view reads the same index and search state.
        Window("MemWhole", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 480, minHeight: 440)
        }
        .defaultSize(width: 860, height: 800)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
