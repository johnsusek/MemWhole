import MemWholeKit
import SwiftUI

struct DocView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let doc: Store.Doc
    /// Runs of body lines, split up so the view can scroll to a match. Only built when the body has matches.
    private let blocks: [(id: Int64, marked: String)]
    private let occurrences: [Occurrence]
    @State private var current = 0

    /// Very large docs (the changelog) make a single Text view slow.
    private static let displayLimit = 200_000
    private static let linesPerBlock = 40

    init(doc: Store.Doc, markedBody: String?) {
        self.doc = doc
        let lines = markedBody.map { Self.truncated($0).split(separator: "\n", omittingEmptySubsequences: false) } ?? []
        blocks = stride(from: 0, to: lines.count, by: Self.linesPerBlock).map { start in
            let end = Swift.min(start + Self.linesPerBlock, lines.count)
            return (Int64(start), lines[start..<end].joined(separator: "\n"))
        }
        occurrences = [Occurrence](blocks: blocks.map { ($0.id, $0.marked) })
    }

    private var cursor: MatchCursor? {
        occurrences.isEmpty ? nil : MatchCursor(count: occurrences.count, current: $current)
    }

    private var fileURL: URL? {
        model.fileURL(forDocPath: doc.path, kind: doc.kind)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    Divider()
                    if blocks.isEmpty {
                        bodyText(Text(Self.truncated(doc.body)))
                    } else {
                        // No spacing, so the blocks read as one continuous text.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(blocks, id: \.id) { block in
                                let ordinal = occurrences.indices.contains(current) && occurrences[current].block == block.id
                                    ? occurrences[current].ordinal : nil
                                bodyText(Text(highlightedMatches(block.marked, current: ordinal)))
                                    .id(block.id)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let cursor { MatchBar(cursor: cursor) }
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: current) { scroll(proxy, animated: true) }
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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                KindBadge(kind: doc.kind)
                Text(Format.date(doc.ts)).font(.caption).foregroundStyle(.secondary)
            }
            Text(doc.title ?? doc.path).font(.title2.weight(.semibold)).textSelection(.enabled)
            if let project = doc.project {
                Label(Format.path(project), systemImage: "folder").font(.caption).foregroundStyle(.secondary)
            }
            Text(doc.path).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }

    private func bodyText(_ text: Text) -> some View {
        text
            .font(isCode ? .body.monospaced() : .body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard occurrences.indices.contains(current) else { return }
        let block = occurrences[current].block
        if animated, !reduceMotion {
            withAnimation { proxy.scrollTo(block, anchor: .center) }
        } else {
            proxy.scrollTo(block, anchor: .center)
        }
    }

    private static func truncated(_ body: String) -> String {
        body.count > displayLimit ? String(body.prefix(displayLimit)) + "\n\n…" : body
    }

    private var isCode: Bool {
        ["snapshot", "config", "plugin-manifest"].contains(doc.kind)
    }
}
