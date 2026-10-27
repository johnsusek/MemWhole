import SwiftUI

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.detail {
        case .session(let session, let messages, let focus, let marked):
            SessionView(session: session, messages: messages, focus: focus, marked: marked)
                .id(model.detailKey)
        case .doc(let doc, let markedBody):
            DocView(doc: doc, markedBody: markedBody)
                .id(model.detailKey)
        case nil:
            ContentUnavailableView("No Selection", systemImage: "text.magnifyingglass",
                                   description: Text("Pick a result to read it in full."))
        }
    }
}
