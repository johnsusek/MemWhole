import MemWholeKit
import SwiftUI

/// Notes the current search finds, newest or best first.
struct ResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ScrollViewReader { proxy in
            List(selection: $model.selection) {
                ForEach(model.hits) { hit in
                    HitRow(hit: hit)
                        .onDrag {
                            model.fileURL(forNotePath: hit.path).flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider()
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Move to Trash", systemImage: "trash", role: .destructive) { model.trash(hit) }
                                .disabled(!model.canTrash)
                        }
                }
                if model.hasMore { loadMoreRow }
            }
            .contextMenu(forSelectionType: Hit.ID.self) { ids in
                if let id = ids.first, let hit = model.hits.first(where: { $0.id == id }) {
                    HitActions(hit: hit)
                }
            } primaryAction: { ids in
                if let id = ids.first, let hit = model.hits.first(where: { $0.id == id }),
                   let url = model.fileURL(forNotePath: hit.path) {
                    model.open(url)
                }
            }
            .onCopyCommand { model.note.map { [NSItemProvider(object: $0.body as NSString)] } ?? [] }
            // Selection can move from the search field, where the list doesn't follow it by itself.
            .onChange(of: model.selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .overlay { emptyState }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isIndexing { IndexStatusView() }
        }
        .navigationTitle("Memories")
        .navigationSubtitle(subtitle)
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 560)
    }

    private var subtitle: String {
        guard let count = model.total else { return "" }
        let noun = model.query.isBlank ? "note" : "result"
        return count == 1 ? "1 \(noun)" : "\(count.formatted()) \(noun)s"
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.hasIndex && !model.isIndexing {
            ContentUnavailableView {
                Label("No Index Yet", systemImage: "tray")
            } description: {
                Text("Choose your ~/.claude folder.")
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

