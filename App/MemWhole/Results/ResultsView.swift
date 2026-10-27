import MemWholeKit
import SwiftUI

/// Notes the current search finds, newest or best first.
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    /// Where each row sits in the window, so a trashed row's ghost can be drawn over it.
    @State private var frames = RowFrames()

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            ForEach(model.hits) { hit in
                HitRow(hit: hit)
                    .opacity(model.forgetting.contains { $0.id == hit.id } ? 0 : 1)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.rows[hit.id] = $0 }
            }
            if model.hasMore { loadMoreRow }
        }
        .contextMenu(forSelectionType: Hit.ID.self) { ids in
            if let id = ids.first, let hit = model.hits.first(where: { $0.id == id }) {
                HitActions(hit: hit)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.list = $0 }
        .overlay(alignment: .topLeading) { forgettingRows }
        .overlay { emptyState }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isIndexing { IndexStatusView() }
        }
        .navigationTitle("Memories")
        .navigationSubtitle(subtitle)
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 560)
        .toolbar {
            ToolbarItem {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort Results By", selection: $model.sort) {
                        Text("Newest First").tag(SearchSort.date)
                        Text("Best Match").tag(SearchSort.relevance)
                    }
                    .pickerStyle(.inline)
                }
                .help("Sort results")
            }
            ToolbarItem {
                Button("Update Index", systemImage: "arrow.clockwise") {
                    model.folderPath == nil ? model.chooseFolderAndIndex() : model.reindex()
                }
                .disabled(model.isIndexing)
                .help(model.folderPath.map { "Update the index of \(Format.path($0)) (⌘R)" } ?? "Choose a folder to index")
            }
        }
    }

    private var subtitle: String {
        guard let count = model.total else { return "" }
        let noun = model.query.isBlank ? "note" : "result"
        return count == 1 ? "1 \(noun)" : "\(count.formatted()) \(noun)s"
    }

    private var forgettingRows: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.forgetting) { hit in
                if let frame = frames.rows[hit.id] {
                    ForgetEffect(hit: hit, size: frame.size)
                        .offset(x: frame.minX - frames.list.minX, y: frame.minY - frames.list.minY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.hasIndex && !model.isIndexing {
            ContentUnavailableView {
                Label("No Index Yet", systemImage: "tray")
            } description: {
                Text("Choose your ~/.claude folder, or a copy of it, to build a search index.")
            } actions: {
                Button("Choose Folder…") { model.chooseFolderAndIndex() }
                    .buttonStyle(.borderedProminent)
            }
        } else if let error = model.errorMessage {
            ContentUnavailableView("Something Went Wrong", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.hits.isEmpty, model.total == 0 {
            if model.query.isBlank {
                ContentUnavailableView("No Memories", systemImage: "brain",
                                       description: Text("No memory notes in the indexed folder yet."))
            } else {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }

    /// Loads the next page when scrolled into view; the button covers a missed appearance.
    private var loadMoreRow: some View {
        HStack {
            if model.isLoadingMore {
                ProgressView().controlSize(.small)
            } else {
                Button("Load More") { model.loadMore() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .selectionDisabled()
        .onAppear { model.loadMore() }
    }
}

/// Row and list frames, kept out of observation so scrolling doesn't re-render the list.
private final class RowFrames {
    var rows: [Hit.ID: CGRect] = [:]
    var list = CGRect.zero
}
