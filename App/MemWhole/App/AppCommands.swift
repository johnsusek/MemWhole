import AppKit
import MemWholeKit
import SwiftUI

/// Menu bar commands. Every action in the window is reachable from here, with a shortcut.
struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        ToolbarCommands()

        CommandGroup(after: .newItem) {
            Button("Index Folder…") { model.chooseFolderAndIndex() }
                .keyboardShortcut("o")
            Button("Update Index") { model.reindex() }
                .keyboardShortcut("r")
                .disabled(model.folderPath == nil || model.isIndexing)
            Divider()
            Button("Open") { model.selectedFileURL.map(model.open) }
                .keyboardShortcut(.downArrow)
                .disabled(model.selectedFileURL == nil)
            Button("Show in Finder") { model.selectedFileURL.map(model.reveal) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedFileURL == nil)
            Divider()
            Button("Move to Trash") {
                // ⌘⌫ in the search field deletes text, as it would without this menu item.
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
                    editor.deleteToBeginningOfLine(nil)
                } else {
                    model.trashSelection()
                }
            }
                .keyboardShortcut(.delete)
                .disabled(!model.canTrashSelection)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Title") { model.selectedHit?.title.map { model.copy(Format.oneLine($0)) } }
                .disabled(model.selectedHit?.title?.isBlank != false)
            Button("Copy Path") { model.selectedHit.map { model.copy($0.path) } }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model.selectedHit == nil)
            Button("Copy Note") { model.selectedHit.map { model.copy(Marks.stripped($0.body)) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.selectedHit == nil)
        }

        // Notes are only ever trashed, never edited: searching replaces the text-editing Find, Spelling and Substitutions menus.
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                Button("Find…") { model.isSearchFocused = true }
                    .keyboardShortcut("f")
                Button("Find Next") { model.stepMatch(by: 1) }
                    .keyboardShortcut("g")
                    .disabled(model.query.isBlank || model.hits.isEmpty)
                Button("Find Previous") { model.stepMatch(by: -1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(model.query.isBlank || model.hits.isEmpty)
            }
        }

        CommandGroup(before: .sidebar) {
            Picker("Sort Results By", selection: $model.sort) {
                Text("Newest First").tag(SearchSort.date)
                Text("Best Match").tag(SearchSort.relevance)
            }
            Divider()
        }
    }
}
