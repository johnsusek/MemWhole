import MemWholeKit
import SwiftUI

/// Menu bar commands. Every action in the window is reachable from here, with a shortcut.
struct AppCommands: Commands {
    @Bindable var model: AppModel
    @FocusedValue(\.matchCursor) private var matchCursor

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Index Folder…") { model.chooseFolderAndIndex() }
                .keyboardShortcut("o")
            Button("Update Index") { model.reindex() }
                .keyboardShortcut("r")
                .disabled(model.folderPath == nil || model.isIndexing)
        }

        // A read-only app: searching replaces the text-editing Find, Spelling and Substitutions menus.
        CommandGroup(replacing: .textEditing) {
            Button("Find…") { model.isSearchFocused = true }
                .keyboardShortcut("f")
            Button("Find Next") { matchCursor?.step(1) }
                .keyboardShortcut("g")
                .disabled((matchCursor?.count ?? 0) < 2)
            Button("Find Previous") { matchCursor?.step(-1) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled((matchCursor?.count ?? 0) < 2)
        }

        CommandGroup(before: .sidebar) {
            ForEach(Array(Scope.allCases.enumerated()), id: \.element) { index, scope in
                Toggle(scope.title, isOn: model.isShowing(scope))
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Picker("Sort Results By", selection: $model.sort) {
                Text("Newest First").tag(SearchSort.date)
                Text("Best Match").tag(SearchSort.relevance)
            }
            Divider()
        }
    }
}
