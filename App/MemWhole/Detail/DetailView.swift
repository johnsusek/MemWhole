import SwiftUI

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let note = model.note {
            NoteView(note: note, markedBody: model.markedBody)
                .id(model.detailKey)
        } else {
            ContentUnavailableView("No Selection", systemImage: "text.magnifyingglass",
                                   description: Text("Pick a note to read it in full."))
        }
    }
}
