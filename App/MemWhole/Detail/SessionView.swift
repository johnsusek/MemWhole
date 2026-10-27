import MemWholeKit
import SwiftUI

struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: Store.Session
    let messages: [Store.Message]
    let marked: [Int64: String]
    private let occurrences: [Occurrence]
    @State private var current: Int

    init(session: Store.Session, messages: [Store.Message], focus: Int64?, marked: [Int64: String]) {
        self.session = session
        self.messages = messages
        self.marked = marked
        occurrences = [Occurrence](blocks: messages.map { ($0.id, marked[$0.id]) })
        // Start at the message the results row showed.
        _current = State(initialValue: occurrences.firstIndex { $0.block == focus } ?? 0)
    }

    private var currentOccurrence: Occurrence? {
        occurrences.indices.contains(current) ? occurrences[current] : nil
    }

    private var cursor: MatchCursor? {
        occurrences.isEmpty ? nil : MatchCursor(count: occurrences.count, current: $current)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(messages) { message in
                        let isCurrent = message.id == currentOccurrence?.block
                        MessageView(message: message, marked: marked[message.id],
                                    currentMatch: isCurrent ? currentOccurrence?.ordinal : nil)
                            .id(message.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let cursor { MatchBar(cursor: cursor) }
            }
            .onAppear {
                if let block = currentOccurrence?.block { proxy.scrollTo(block, anchor: .center) }
            }
            .onChange(of: current) {
                guard let block = currentOccurrence?.block else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(block, anchor: .center) }
            }
        }
        .focusedSceneValue(\.matchCursor, cursor)
        .toolbar {
            ToolbarItem {
                Button("Copy Session ID", systemImage: "doc.on.doc") { model.copy(session.id) }
                    .help("Copy the session ID")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title.map(Format.oneLine) ?? "(untitled)")
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Label(Format.path(session.project), systemImage: "folder")
                if let branch = session.branch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                }
                Label("\(Format.date(session.firstTS)) → \(Format.date(session.lastTS))", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(session.id)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Divider().padding(.top, 8)
        }
    }
}
