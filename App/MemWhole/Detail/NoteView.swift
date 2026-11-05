import MemWholeKit
import SwiftUI

struct NoteView: View {
    @Environment(AppModel.self) private var model
    let note: Store.Note
    private let rendered: RenderedNote
    @State private var current = 0

    init(note: Store.Note, markedBody: String?) {
        self.note = note
        rendered = NoteRenderer.render(markedBody ?? note.body, marks: (Marks.open, Marks.close))
    }

    private var cursor: MatchCursor? {
        rendered.matches.isEmpty ? nil : MatchCursor(count: rendered.matches.count, current: $current)
    }

    private var fileURL: URL? {
        model.fileURL(forNotePath: note.path)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let cursor { MatchBar(cursor: cursor) }
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            Divider()
            NoteTextView(rendered: rendered, current: current)
        }
        .focusedSceneValue(\.matchCursor, cursor)
        .toolbar {
            ToolbarItem {
                Button("Show in Finder", systemImage: "folder") {
                    if let fileURL { model.reveal(fileURL) }
                }
                .disabled(fileURL == nil)
                .help("Show this file in Finder")
            }
            ToolbarItem {
                Button("Move to Trash", systemImage: "trash") { model.trashSelection() }
                    .disabled(!model.canTrashSelection)
                    .help("Move this note to the Trash (⌘⌫)")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.date(note.ts)).font(.caption).foregroundStyle(.secondary)
            Text(note.title ?? note.path).font(.title2.weight(.semibold)).textSelection(.enabled)
            if let project = note.project {
                Label(Format.path(project), systemImage: "folder").font(.caption).foregroundStyle(.secondary)
            }
            Text(note.path).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }
}
