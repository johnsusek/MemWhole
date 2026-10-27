import SwiftUI

/// The notes the current search finds, and the selected note in full.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            ResultsView()
        } detail: {
            DetailView()
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search memories")
        .searchFocusedIfAvailable($isSearchFocused)
        .onChange(of: model.isSearchFocused) { _, focused in
            isSearchFocused = focused
        }
        .onChange(of: isSearchFocused) { _, focused in
            model.isSearchFocused = focused
        }
    }
}
