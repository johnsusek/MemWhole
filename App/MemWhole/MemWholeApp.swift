import SwiftUI

@main
struct MemWholeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Index Folder…") { model.chooseFolderAndIndex() }
                    .keyboardShortcut("o")
                Button("Update Index") { model.reindex() }
                    .keyboardShortcut("r")
                    .disabled(model.folderPath == nil || model.isIndexing)
            }
        }
    }
}
