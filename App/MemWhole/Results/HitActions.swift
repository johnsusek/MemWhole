import MemWholeKit
import SwiftUI

/// Context menu items for a result.
struct HitActions: View {
    @Environment(AppModel.self) private var model
    let hit: Hit

    var body: some View {
        if let url = model.fileURL(forNotePath: hit.path) {
            Button("Open") { model.open(url) }
            Button("Show in Finder") { model.reveal(url) }
            Divider()
        }
        if let title = hit.title, !title.isBlank {
            Button("Copy Title") { model.copy(Format.oneLine(title)) }
        }
        Button("Copy Path") { model.copy(hit.path) }
        Divider()
        Button("Move to Trash") { model.trash(hit) }
            .disabled(!model.canTrash)
    }
}
