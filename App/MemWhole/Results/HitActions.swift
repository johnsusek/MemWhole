import MemWholeKit
import SwiftUI

/// Context menu items for a result.
struct HitActions: View {
    @Environment(AppModel.self) private var model
    let hit: Hit

    var body: some View {
        if let title = hit.title, !title.isBlank {
            Button("Copy Title") { model.copy(Format.oneLine(title)) }
        }
        Button("Copy Path") { model.copy(hit.path) }
        if let url = model.fileURL(forNotePath: hit.path) {
            Divider()
            Button("Show in Finder") { model.reveal(url) }
        }
    }
}
