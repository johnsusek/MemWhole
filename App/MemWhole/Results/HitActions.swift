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
        if let sessionID = hit.sessionID {
            Button("Copy Session ID") { model.copy(sessionID) }
        }
        if let path = hit.path {
            Button("Copy Path") { model.copy(path) }
        }
        if hit.type == "doc", let url = model.fileURL(forDocPath: hit.path, kind: hit.role) {
            Divider()
            Button("Show in Finder") { model.reveal(url) }
        }
    }
}
