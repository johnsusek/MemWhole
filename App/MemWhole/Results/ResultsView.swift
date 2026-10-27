import MemWholeKit
import SwiftUI

/// Results for the current search and scope, newest or best first.
struct ResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            ForEach(model.hits) { HitRow(hit: $0) }
            if model.hasMore { loadMoreRow }
        }
        .contextMenu(forSelectionType: Hit.ID.self) { ids in
            if let id = ids.first, let hit = model.hits.first(where: { $0.id == id }) {
                HitActions(hit: hit)
            }
        }
        .overlay { emptyState }
        .navigationTitle(model.scope.title)
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
        let count = model.count(for: model.scope)
        guard model.searchCounts != nil else { return "" }
        let noun = model.query.isBlank ? "item" : "result"
        return count == 1 ? "1 \(noun)" : "\(count.formatted()) \(noun)s"
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
        } else if model.hits.isEmpty, model.searchCounts != nil, model.count(for: model.scope) == 0 {
            if model.query.isBlank {
                ContentUnavailableView("No \(model.scope.title)", systemImage: model.scope.systemImage,
                                       description: Text("Nothing in the index yet."))
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
