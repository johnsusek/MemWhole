import MemWholeKit
import SwiftUI

/// The window's toolbar, arranged with View > Customize Toolbar…
struct MainToolbar: CustomizableToolbarContent {
  @Bindable var model: AppModel

  var body: some CustomizableToolbarContent {
    ToolbarItem(id: "sort") {
      Menu("Sort", systemImage: "arrow.up.arrow.down") {
        Picker("Sort Results By", selection: $model.sort) {
          Text("Newest First").tag(SearchSort.date)
          Text("Best Match").tag(SearchSort.relevance)
        }
        .pickerStyle(.inline)
      }
      .help("Sort results")
    }

    ToolbarItem(id: "update") {
      Button("Update Index", systemImage: "arrow.clockwise") {
        model.folderPath == nil ? model.chooseFolderAndIndex() : model.reindex()
      }
      .disabled(model.isIndexing)
      .help(model.folderPath.map { "Update the index of \(Format.path($0)) (⌘R)" } ?? "Choose a folder to index")
    }

    ToolbarItem(id: "reveal") {
      Button("Show in Finder", systemImage: "folder") { model.selectedFileURL.map(model.reveal) }
        .disabled(model.selectedFileURL == nil)
        .help("Show this file in Finder (⇧⌘R)")
    }

    ToolbarItem(id: "trash") {
      Button("Move to Trash", systemImage: "trash") { model.trashSelection() }
        .disabled(!model.canTrashSelection)
        .help("Move this note to the Trash (⌘⌫)")
    }
  }
}
